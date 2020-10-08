unit Android.BroadcastReceiver;

interface
Uses
  System.Classes
  ,System.SysUtils
  {$IFDEF ANDROID}
  ,Androidapi.JNI.Embarcadero
  ,Androidapi.JNI.GraphicsContentViewText
  ,Androidapi.helpers
  ,Androidapi.JNIBridge
  ,FMX.Helpers.Android
  {$ENDIF}
  ;

type

  {$IFNDEF ANDROID}
  JIntent = class end; // FI:C104
  JContext = class end; // FI:C104
  {$ENDIF}

  TBroadcastReceiver= class;
  TOnReceive = procedure (Context: JContext; Intent: JIntent)of object;

  {$IFDEF ANDROID}
  TListener = class(TJavaLocal, JFMXBroadcastReceiverListener)
    private
      FOwner: TBroadcastReceiver;
    public
      constructor Create(AOwner: TBroadcastReceiver);
      procedure onReceive(context: JContext; intent: JIntent); cdecl;
  end;
  {$ENDIF}


  TBroadcastReceiver = class(TComponent)
    private
      {$IFDEF ANDROID}
      FReceiver: JBroadcastReceiver;
      FListener : TListener;
      {$ENDIF}
      FOnReceive: TOnReceive;
      FItems: TStringList;
      function GetItem(const Index: Integer): String;

    public
      constructor Create(AOwner: TComponent); override;
      destructor  Destroy; override;
      procedure SendBroadcast(const Value: String);
      procedure Add(const Value: String);
      procedure Delete(Index: Integer);
      procedure Clear;
      function Remove(const Value: String): Integer;
      function First: String;
      function Last: String;
      function HasPermission(const Permission: string): Boolean;
      procedure RegisterReceive;
      property Item[const Index: Integer]: String read GetItem; default;
      property Items: TStringList read FItems write FItems;
    published
      property onReceive: TOnReceive read FOnReceive write FOnReceive;
  end;

procedure Register;

implementation

{$IFDEF ANDROID}
uses
  Androidapi.JNI.App,
  Androidapi.JNI.JavaTypes;
{$ENDIF ANDROID}

procedure Register;
begin
  RegisterComponents('Android', [TBroadcastReceiver]);
end;

{ TBroadcastReceiver }

procedure TBroadcastReceiver.Add(const Value: String);
{$IFDEF ANDROID}
var
  Filter: JIntentFilter;
{$ENDIF}
begin
  {$IFDEF ANDROID}
  if (FListener = nil) or (FReceiver = nil) then
    Raise Exception.Create('First use RegisterReceive!');
  {$ENDIF}

  if FItems <> nil then
    if FItems.IndexOf(Value) = -1 then
    begin
    {$IFDEF ANDROID}
      filter := TJIntentFilter.Create;
      filter.addAction(StringToJString(Value));
      SharedActivityContext.registerReceiver(FReceiver,filter);
    {$ENDIF}
      FItems.Add(Value);
    end;
end;

procedure TBroadcastReceiver.Clear;
begin
  FItems.Clear;
end;

constructor TBroadcastReceiver.Create(AOwner: TComponent);
begin
  inherited;
  FItems := TStringList.Create;
end;

procedure TBroadcastReceiver.Delete(Index: Integer);
begin
  if FItems <> nil then
  begin
    FItems.Delete(Index);
    {$IFDEF ANDROID}
      SharedActivity.UnregisterReceiver(FReceiver);
      RegisterReceive;
    {$ENDIF}
  end;
end;

destructor TBroadcastReceiver.Destroy;
begin
  FItems.Free;
{$IFDEF ANDROID}
  if FReceiver <> nil  then
    SharedActivity.UnregisterReceiver(FReceiver);
{$ENDIF}
  inherited;
end;

function TBroadcastReceiver.First: String;
begin
  Result := FItems[0];
end;

function TBroadcastReceiver.GetItem(const Index: Integer): String;
begin
  Result := FItems[Index];
end;

function TBroadcastReceiver.HasPermission(const Permission: string): Boolean;
{$IFDEF ANDROID}
begin
  //Permissions listed at http://d.android.com/reference/android/Manifest.permission.html
  Result := SharedActivity.checkCallingOrSelfPermission(
    StringToJString(Permission)) =
    TJPackageManager.JavaClass.PERMISSION_GRANTED
{$ELSE}
begin
  Result := False;
{$ENDIF}
end;

function TBroadcastReceiver.Last: String;
begin
  Result := FItems[FItems.Count];
end;

procedure TBroadcastReceiver.RegisterReceive;
{$IFDEF ANDROID}
var
  I: Integer;
begin
  if FListener = nil then
    FListener := TListener.Create(Self);
  if FReceiver = nil then
    FReceiver := TJFMXBroadcastReceiver.JavaClass.init(FListener);
  if FItems <> nil then
    if FItems.Count > 0 then
      for I := 0 to FItems.Count -1 do
        Add(FItems[I]);
{$ELSE}
begin // FI:W519
{$ENDIF}
end;

function TBroadcastReceiver.Remove(const Value: String): Integer;
begin
  Result := FItems.IndexOf(Value);
  if Result > -1 then
    FItems.Delete(Result);
end;

procedure TBroadcastReceiver.SendBroadcast(const Value: String);
{$IFDEF ANDROID}
var
  Inx: JIntent;
begin
  Inx := TJIntent.Create;
  Inx.setAction(StringToJString(Value));
  SharedActivityContext.sendBroadcast(Inx);
{$ELSE}
begin // FI:W519
{$ENDIF}
end;

{$IFDEF ANDROID}
constructor TListener.Create(AOwner: TBroadcastReceiver);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TListener.onReceive(context: JContext; intent: JIntent);
begin
  if Assigned(FOwner.onReceive) then
    FOwner.onReceive(Context, Intent);
end;

{$ENDIF}

end.
