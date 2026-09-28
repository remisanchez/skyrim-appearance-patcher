{
  AP_Utils.pas
  Shared helpers for the NPC Appearance Patcher scripts: dialogs, record IDs,
  record queries and config file saving.
}

unit AP_Utils;

interface

function AskInputDialog(const caption, prompt: string; var resultStr: string): Boolean;
function EditorIDInputValidation(const s: string): Boolean;
function IsOfficialMaster(const fileName: string): Boolean;
function PadLeftZero(const s: string; targetLength: Integer): string;
function GetLocalFormIDHex(rec: IInterface): string;
function GetSkyPatcherID(rec: IInterface): string;
function GetLinkedMasterRecord(rec: IInterface; const path: string): IInterface;
function SameLinkedRecord(a, b: IInterface): Boolean;
function FindNPCByEditorID(const edid: string): IInterface;
function IsNPCFemale(npc: IInterface): Boolean;
function IsNPCUsingTraits(npc: IInterface): Boolean;
function GetFaceGenRelPath(const pluginName, formID: string; isMesh: Boolean): string;
function GetNPCFaceGenRelPath(npc: IInterface; isMesh: Boolean): string;
function DataResourceExists(const relPath: string): Boolean;
function CopyResource(const relPath, outPath: string): Boolean;
function WriteExportFile(sl: TStringList; const fileName: string): Boolean;
function SaveExportList(sl: TStringList; const saveDir, fileBaseName, saveLabel: string): Boolean;

implementation

// Text input dialog. InputQuery does not return the typed text in xEdit scripts.
// Returns false if cancelled.
function AskInputDialog(const caption, prompt: string; var resultStr: string): Boolean;
var
  form: TForm;
  lbl: TLabel;
  edt: TEdit;
  btnOK, btnCancel: TButton;
begin
  Result := False;

  form := TForm.Create(nil);
  try
    form.Caption := caption;
    form.ClientWidth := 400;
    form.ClientHeight := 130;
    form.Position := poScreenCenter;
    form.BorderStyle := bsDialog;

    lbl := TLabel.Create(form);
    lbl.Parent := form;
    lbl.Left := 10;
    lbl.Top := 10;
    lbl.Width := 380;
    lbl.Height := 36;
    lbl.AutoSize := false;
    lbl.WordWrap := true;
    lbl.Caption := prompt;

    edt := TEdit.Create(form);
    edt.Parent := form;
    edt.Left := 10;
    edt.Top := 52;
    edt.Width := 380;
    edt.Text := resultStr;

    btnOK := TButton.Create(form);
    btnOK.Parent := form;
    btnOK.Caption := 'OK';
    btnOK.ModalResult := mrOk;
    btnOK.Width := 75;
    btnOK.Top := 90;
    btnOK.Left := (form.ClientWidth div 2) - btnOK.Width - 10;

    btnCancel := TButton.Create(form);
    btnCancel.Parent := form;
    btnCancel.Caption := 'Cancel';
    btnCancel.ModalResult := mrCancel;
    btnCancel.Width := 75;
    btnCancel.Top := 90;
    btnCancel.Left := (form.ClientWidth div 2) + 10;

    if form.ShowModal = mrOk then begin
      Result := True;
      resultStr := edt.Text;
    end;
  finally
    form.Free;
  end;
end;

// Letters and digits only. Uses Pos/Copy: char comparisons are unreliable in xEdit scripts.
function EditorIDInputValidation(const s: string): Boolean;
var
  i: Integer;
begin
  Result := Length(s) > 0;
  for i := 1 to Length(s) do
    if Pos(Copy(s, i, 1), 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789') = 0 then
      Result := false;
end;

function IsOfficialMaster(const fileName: string): Boolean;
begin
  Result :=
    SameText(fileName, 'Skyrim.esm') or
    SameText(fileName, 'Update.esm') or
    SameText(fileName, 'Dawnguard.esm') or
    SameText(fileName, 'HearthFires.esm') or
    SameText(fileName, 'Dragonborn.esm') or
    SameText(fileName, '_ResourcePack.esl') or
    SameText(fileName, 'ccBGSSSE001-Fish.esm') or
    SameText(fileName, 'ccBGSSSE025-AdvDSGS.esm') or
    SameText(fileName, 'ccBGSSSE037-Curios.esl') or
    SameText(fileName, 'ccQDRSSE001-SurvivalMode.esl');
end;

function PadLeftZero(const s: string; targetLength: Integer): string;
begin
  Result := s;
  while Length(Result) < targetLength do
    Result := '0' + Result;
end;

// FormID inside the defining plugin, without the master index (e.g. "13BB7")
function GetLocalFormIDHex(rec: IInterface): string;
begin
  Result := IntToHex(FormID(MasterOrSelf(rec)) and $FFFFFF, 1);
end;

// SkyPatcher: "Plugin.esp|13BB7"
function GetSkyPatcherID(rec: IInterface): string;
var
  m: IInterface;
begin
  Result := '';
  if not Assigned(rec) then
    Exit;

  m := MasterOrSelf(rec);
  Result := GetFileName(GetFile(m)) + '|' + GetLocalFormIDHex(m);
end;

// Master record linked by the element at path, or nil
function GetLinkedMasterRecord(rec: IInterface; const path: string): IInterface;
var
  elem: IInterface;
begin
  Result := nil;
  elem := ElementByPath(rec, path);
  if Assigned(elem) then
    Result := MasterOrSelf(LinksTo(elem));
end;

// Compares records by load order FormID: raw FormIDs are relative to each
// plugin's master list and cannot be compared across plugins.
function SameLinkedRecord(a, b: IInterface): Boolean;
begin
  if not Assigned(a) or not Assigned(b) then
    Result := Assigned(a) = Assigned(b)
  else
    Result := GetLoadOrderFormID(MasterOrSelf(a)) = GetLoadOrderFormID(MasterOrSelf(b));
end;

// Master NPC_ record with this EditorID, or nil
function FindNPCByEditorID(const edid: string): IInterface;
var
  i: integer;
  group, rec: IInterface;
begin
  Result := nil;
  for i := 0 to Pred(FileCount) do begin
    group := GroupBySignature(FileByIndex(i), 'NPC_');
    if Assigned(group) and not Assigned(Result) then begin
      rec := MainRecordByEditorID(group, edid);
      if Assigned(rec) then
        Result := MasterOrSelf(rec);
    end;
  end;
end;

function IsNPCFemale(npc: IInterface): Boolean;
begin
  Result := GetElementEditValues(npc, 'ACBS - Configuration\Flags\Female') = '1';
end;

function IsNPCUsingTraits(npc: IInterface): Boolean;
var
  templateFlags: IInterface;
begin
  Result := False;
  templateFlags := ElementByPath(npc, 'ACBS - Configuration\Template Flags');
  if Assigned(templateFlags) then
    Result := GetElementNativeValues(templateFlags, 'Use Traits') <> 0;
end;

// FaceGen path relative to Data. formID: 8 hex digits, without load order index.
function GetFaceGenRelPath(const pluginName, formID: string; isMesh: Boolean): string;
begin
  if isMesh then
    Result := 'meshes\actors\character\FaceGenData\FaceGeom\' + pluginName + '\' + formID + '.nif'
  else
    Result := 'textures\actors\character\FaceGenData\FaceTint\' + pluginName + '\' + formID + '.dds';
end;

function GetNPCFaceGenRelPath(npc: IInterface; isMesh: Boolean): string;
var
  m: IInterface;
begin
  m := MasterOrSelf(npc);
  Result := GetFaceGenRelPath(GetFileName(GetFile(m)), PadLeftZero(GetLocalFormIDHex(m), 8), isMesh);
end;

// Last container (BSA or folder) holding relPath, '' if none.
// Only knows files present when xEdit started.
function FindResourceContainer(const relPath: string): string;
var
  containers: TStringList;
begin
  Result := '';
  containers := TStringList.Create;
  try
    ResourceCount(relPath, containers);
    if containers.Count > 0 then
      Result := containers[containers.Count - 1];
  finally
    containers.Free;
  end;
end;

// Loose file in Data or file in an archive
function DataResourceExists(const relPath: string): Boolean;
begin
  Result := FileExists(DataPath + relPath) or (FindResourceContainer(relPath) <> '');
end;

// Copies a loose or archived file, as the v2 PreProcessor: the result of the
// copy is not used (unreliable in xEdit scripts), only the source is checked.
// Returns true if the source exists.
function CopyResource(const relPath, outPath: string): Boolean;
var
  container, tempDir, srcPath, dstPath, extractedPath: string;
begin
  Result := false;
  // Plain variables for PChar, as in v2 (no expression inside PChar)
  srcPath := DataPath + relPath;
  dstPath := outPath;
  if not DirectoryExists(ExtractFilePath(dstPath)) then
    ForceDirectories(ExtractFilePath(dstPath));

  if FileExists(srcPath) then begin
    if CopyFile(PChar(srcPath), PChar(dstPath), False) then
      AddMessage('  Copied: ' + srcPath + ' -> ' + dstPath)
    else
      AddMessage('  CopyFile returned false: ' + srcPath + ' -> ' + dstPath);
    Result := true;
  end
  else begin
    container := FindResourceContainer(relPath);
    if container <> '' then begin
      // ResourceCopy writes to <folder> + relPath: extract next to outPath, then rename
      tempDir := ExtractFilePath(dstPath) + '_extract\';
      extractedPath := tempDir + relPath;
      ResourceCopy(container, relPath, tempDir);
      if RenameFile(PChar(extractedPath), PChar(dstPath)) then
        AddMessage('  Extracted: ' + relPath + ' from ' + container + ' -> ' + dstPath)
      else
        AddMessage('  RenameFile returned false: ' + extractedPath + ' -> ' + dstPath);
      Result := true;
    end
    else
      AddMessage('  Not found: ' + relPath);
  end;
end;

// Writes sl to fileName, asking to append or overwrite if it exists.
// Returns false if the user cancelled.
function WriteExportFile(sl: TStringList; const fileName: string): Boolean;
var
  existingContent: TStringList;
  userChoice: integer;
begin
  Result := false;

  if not DirectoryExists(ExtractFilePath(fileName)) then
    ForceDirectories(ExtractFilePath(fileName));

  if FileExists(fileName) then begin
    userChoice := MessageDlg(
      'File already exists: ' + fileName + #13#10 + #13#10 +
      'Yes: Append to existing file' + #13#10 +
      'No: Overwrite the file' + #13#10 +
      'Cancel: Choose another file',
      mtConfirmation, [mbYes, mbNo, mbCancel], 0);

    if userChoice = mrYes then begin
      AddMessage('Appending to ' + fileName);
      existingContent := TStringList.Create;
      try
        existingContent.LoadFromFile(fileName);
        existingContent.AddStrings(sl);
        existingContent.SaveToFile(fileName);
      finally
        existingContent.Free;
      end;
      Result := true;
    end
    else if userChoice = mrNo then begin
      AddMessage('Overwriting ' + fileName);
      sl.SaveToFile(fileName);
      Result := true;
    end;
  end
  else begin
    AddMessage('Saving ' + fileName);
    sl.SaveToFile(fileName);
    Result := true;
  end;
end;

// Offers the default path first: the save dialog may ignore InitialDir
// (Windows remembers the last folder, MO2 virtual folders are not always visible).
function SaveExportList(sl: TStringList; const saveDir, fileBaseName, saveLabel: string): Boolean;
var
  dlgSave: TSaveDialog;
  defaultFileName: string;
  userChoice: integer;
  askFileName, done: Boolean;
begin
  Result := false;
  askFileName := false;
  defaultFileName := saveDir + fileBaseName + '.ini';

  userChoice := MessageDlg(
    'Save ' + saveLabel + ' to:' + #13#10 + defaultFileName + #13#10 + #13#10 +
    'Yes: Save here' + #13#10 +
    'No: Choose another location' + #13#10 +
    'Cancel: Do not save',
    mtConfirmation, [mbYes, mbNo, mbCancel], 0);

  if userChoice = mrYes then begin
    Result := WriteExportFile(sl, defaultFileName);
    if not Result then
      askFileName := true;
  end
  else if userChoice = mrNo then
    askFileName := true
  else
    AddMessage('Save cancelled by user (' + saveLabel + ')');

  if not askFileName then
    Exit;

  if not DirectoryExists(saveDir) then
    ForceDirectories(saveDir);

  done := false;
  dlgSave := TSaveDialog.Create(nil);
  try
    dlgSave.Options    := dlgSave.Options - [ofOverwritePrompt];
    dlgSave.Filter     := 'Ini (*.ini)|*.ini';
    dlgSave.Title      := 'Save ' + saveLabel;
    dlgSave.InitialDir := saveDir;
    dlgSave.FileName   := defaultFileName;

    // No Break/Exit inside repeat: known xEdit parser issue
    repeat
      if not dlgSave.Execute then begin
        AddMessage('Save cancelled by user (' + saveLabel + ')');
        done := true;
      end
      else if WriteExportFile(sl, dlgSave.FileName) then begin
        Result := true;
        done := true;
      end;
    until done;
  finally
    dlgSave.Free;
  end;
end;

end.
