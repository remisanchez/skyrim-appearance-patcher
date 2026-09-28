{
  AP_LeveledLists.pas
  Leveled list (LVLN) index and SkyPatcher leveledList rules: the original NPC
  is removed from each list and the isolated replacer NPC is added with the
  same level and count.
}

unit AP_LeveledLists;

uses 'AP\AP_Utils';

interface

function BuildLVLNMap(useFormID: boolean): TStringList;
procedure FreeLVLNMap(map: TStringList);
function FindLVLNEntries(map: TStringList; npc: IInterface): integer;
procedure AddLLRules(sl, map: TStringList; idx: integer; targetRecord, replacerRecord: IInterface; useFormID, disableAll: boolean);
function CountPlacedReferences(npc: IInterface): integer;

implementation

const
  ENTRY_SEPARATOR = #9;

function GetNPCKey(npc: IInterface): string;
begin
  Result := IntToHex(GetLoadOrderFormID(MasterOrSelf(npc)), 8);
end;

// Map: Name = NPC load order FormID, Object = TStringList of
// "<LVLN SkyPatcher ID><TAB><level>~<count>", entries of a LVLN kept together.
// Entries are read from the winning override of each LVLN.
function BuildLVLNMap(useFormID: boolean): TStringList;
var
  i, j, k, idx, entryCount: integer;
  lvlnGroup, lvln, entries, entry, ref: IInterface;
  lvlnID, npcKey, level, count: string;
  npcEntries: TStringList;
begin
  Result := TStringList.Create;
  Result.Sorted := true;
  Result.Duplicates := dupIgnore;
  entryCount := 0;

  for i := 0 to Pred(FileCount) do begin
    lvlnGroup := GroupBySignature(FileByIndex(i), 'LVLN');
    if not Assigned(lvlnGroup) then
      Continue;

    for j := 0 to Pred(ElementCount(lvlnGroup)) do begin
      lvln := ElementByIndex(lvlnGroup, j);
      // Visit each LVLN once, through its master record
      if not IsMaster(lvln) then
        Continue;

      entries := ElementByPath(WinningOverride(lvln), 'Leveled List Entries');
      lvlnID := GetSkyPatcherID(lvln, useFormID);
      // LVLN without EditorID: fall back to its FormID
      if lvlnID = '' then
        lvlnID := GetSkyPatcherID(lvln, true);
      if not Assigned(entries) then
        Continue;

      for k := 0 to Pred(ElementCount(entries)) do begin
        entry := ElementByIndex(entries, k);
        ref := LinksTo(ElementByPath(entry, 'LVLO\Reference'));
        if not Assigned(ref) then
          Continue;
        if Signature(ref) <> 'NPC_' then
          Continue;

        level := GetElementEditValues(entry, 'LVLO\Level');
        count := GetElementEditValues(entry, 'LVLO\Count');
        if level = '' then
          level := '1';
        if count = '' then
          count := '1';

        npcKey := GetNPCKey(ref);
        idx := Result.IndexOf(npcKey);
        if idx = -1 then begin
          npcEntries := TStringList.Create;
          Result.AddObject(npcKey, npcEntries);
        end
        else
          npcEntries := TStringList(Result.Objects[idx]);

        npcEntries.Add(lvlnID + ENTRY_SEPARATOR + level + '~' + count);
        Inc(entryCount);
      end;
    end;
  end;

  AddMessage('LVLN index: ' + IntToStr(Result.Count) + ' NPCs, ' + IntToStr(entryCount) + ' entries.');
end;

procedure FreeLVLNMap(map: TStringList);
var
  i: integer;
begin
  if not Assigned(map) then
    Exit;
  for i := 0 to map.Count - 1 do
    TStringList(map.Objects[i]).Free;
  map.Free;
end;

// Index of the NPC in the map, -1 if it is in no leveled list
function FindLVLNEntries(map: TStringList; npc: IInterface): integer;
begin
  Result := map.IndexOf(GetNPCKey(npc));
end;

// For each leveled list containing the target NPC:
//   filterByLLNPCs=<LVLN>:removeFromLLs=<target>
//   filterByLLNPCs=<LVLN>:addToLLs=<replacer>~level~count, ...
// Always SkyPatcher syntax (';' comments), whatever the NPC framework.
procedure AddLLRules(sl, map: TStringList; idx: integer; targetRecord, replacerRecord: IInterface; useFormID, disableAll: boolean);
var
  entries: TStringList;
  i, sepPos: integer;
  coChar, targetID, replacerID, lvlnID, currentLvlnID, levelCount, addList: string;
begin
  entries := TStringList(map.Objects[idx]);

  coChar := '';
  if disableAll then
    coChar := ';';

  targetID   := GetSkyPatcherID(targetRecord, useFormID);
  replacerID := GetSkyPatcherID(replacerRecord, useFormID);

  sl.Add(';' + GetElementEditValues(targetRecord, 'FULL'));
  sl.Add(';Form ID: ' + GetLocalFormIDHex(targetRecord) + '  Editor ID: ' + EditorID(targetRecord) +
    '  ->  ' + EditorID(replacerRecord));

  // One extra iteration flushes the last LVLN
  currentLvlnID := '';
  addList := '';
  for i := 0 to entries.Count do begin
    lvlnID := '';
    if i < entries.Count then begin
      sepPos     := Pos(ENTRY_SEPARATOR, entries[i]);
      lvlnID     := Copy(entries[i], 1, sepPos - 1);
      levelCount := Copy(entries[i], sepPos + 1, Length(entries[i]) - sepPos);
    end;

    if (lvlnID <> currentLvlnID) and (currentLvlnID <> '') then begin
      sl.Add(coChar + 'filterByLLNPCs=' + currentLvlnID + ':removeFromLLs=' + targetID);
      sl.Add(coChar + 'filterByLLNPCs=' + currentLvlnID + ':addToLLs=' + addList);
      addList := '';
    end;

    if i < entries.Count then begin
      if addList <> '' then
        addList := addList + ', ';
      addList := addList + replacerID + '~' + levelCount;
      currentLvlnID := lvlnID;
    end;
  end;

  sl.Add('');
end;

// ACHR references of the NPC (requires xEdit reference info)
function CountPlacedReferences(npc: IInterface): integer;
var
  i: integer;
  m: IInterface;
begin
  Result := 0;
  m := MasterOrSelf(npc);
  for i := 0 to Pred(ReferencedByCount(m)) do
    if Signature(ReferencedByIndex(m, i)) = 'ACHR' then
      Inc(Result);
end;

end.
