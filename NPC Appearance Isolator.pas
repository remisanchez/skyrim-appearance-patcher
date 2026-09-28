{
  NPC Appearance Isolator.pas
  Runs the isolation phase alone (see AP\AP_Isolator.pas). Then run
  "NPC Appearance Patcher" without Integration Mode.
}

unit AppearanceIsolator;

uses 'AP\AP_Isolator';

const
  OUTPUT_ROOT = 'NPC Appearance Patcher';

var
  initialized: boolean;

function Initialize: integer;
begin
  Result := IsolatorInitialize;
  initialized := Result = 0;
end;

function Process(e: IInterface): integer;
var
  newRecord: IInterface;
begin
  Result := IsolatorProcess(e, newRecord, OUTPUT_ROOT);
end;

function Finalize: integer;
begin
  Result := 0;
  if initialized then
    IsolatorFinalize;
end;

end.
