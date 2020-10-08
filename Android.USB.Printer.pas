unit Android.USB.Printer;

interface

{$IFDEF DEBUG}
{$DEFINE ANDROID_USB_DEBUG}
{$ENDIF DEBUG}

uses
  Classes, SysUtils,
  Androidapi.Helpers, Androidapi.JNIBridge,
  Androidapi.JNI.JavaTypes, Androidapi.JNI.App, Androidapi.Jni,
  Androidapi.JNI.GraphicsContentViewText,
  Android.BroadcastReceiver,
  android.hardware.usb.UsbConstants,
  android.hardware.usb.UsbDevice,
  android.hardware.usb.UsbInterface,
  android.hardware.usb.UsbEndpoint,
  android.hardware.usb.UsbDeviceConnection,
  android.hardware.usb.UsbManager,
  Android.USB;

type
  TUSBDeviceWriter = class(TUSBDevicesAndroid)
  protected
    const
      ACTION_USB_PERMISSION = 'com.android.example.USB_PERMISSION';
    class function GetDeviceByName(AUSBDevices: JArrayList;
      const AName: string): JUsbDevice;
    class function FindInterfaceForDevice(AUSBDevice: JUSBDevice;
      AUSBClass: Integer;
      out AUSBInterface: JUSBInterface): Boolean;
    class function FindBulkEndpointForInterface(AUSBInterface: JUSBInterface;
      out AUsbEndpoint: JUsbEndpoint): Boolean;
    class function WriteToDevice(AUSBDeviceConnection: JUsbDeviceConnection;
      AUsbEndpoint: JUsbEndpoint;
      ABytes: TBytes): Integer;
  public
  end;

  TPrintEventHandler = class
  public
    procedure Received(AContext: JContext; AIntent: JIntent);
  end;

  TAndroidUSBPrinter = class(TUSBDeviceWriter)
  protected
    class var FPrintEventHandler: TPrintEventHandler;
  public
    class function Find(out AUSBPrinters: JArrayList): Boolean;
    class procedure Print(APrinter: JUsbDevice; const AText: string);
  end;

implementation

uses
  StrUtils, Math
  {$IFDEF ANDROID_USB_DEBUG}
  , FMX.Types
  {$ENDIF ANDROID_USB_DEBUG}
  ;

var
  __BroadcastReceiver: TBroadcastReceiver;

const
  PRINTER_TEXT = 'PRINTER_TEXT';

{$IFDEF ANDROID_USB_DEBUG}
function BytesToHexStr(const ABytes: TBytes): string;
var
  i: Integer;
begin
  Result := EmptyStr;
  for i := Low(ABytes) to High(ABytes) do
    Result := Result + Format('\x%.2x', [ABytes[i]]);
end;
{$ENDIF ANDROID_USB_DEBUG}

{ TUSBDeviceWriter }

class function TUSBDeviceWriter.FindBulkEndpointForInterface(
  AUSBInterface: JUSBInterface; out AUsbEndpoint: JUsbEndpoint): Boolean;
var
  i: Integer;
begin
  for i := 0 to AUSBInterface.getEndpointCount - 1 do
  begin
    AUsbEndpoint := AUSBInterface.getEndpoint(i);
    if AUsbEndpoint.getType <> TJUsbConstantsUSB_ENDPOINT_XFER_BULK then
      Continue;
    if AUsbEndpoint.getDirection = TJUsbConstantsUSB_DIR_OUT then
    begin
      Result := True;
      Exit;
    end;
  end;
  Result := False;
  AUsbEndpoint := nil;
end;

class function TUSBDeviceWriter.FindInterfaceForDevice(
  AUSBDevice: JUSBDevice;
  AUSBClass: Integer;
  out AUSBInterface: JUSBInterface): Boolean;
var
  i: Integer;
  {$IFDEF ANDROID_USB_DEBUG}
  s: string;
  {$ENDIF ANDROID_USB_DEBUG}
begin
  {$IFDEF ANDROID_USB_DEBUG}
  s := Format('USB device (%.4x:%.4x) interfaces (count: %d):',
    [AUSBDevice.getVendorId, AUSBDevice.getProductId, AUSBDevice.getInterfaceCount]);
  Log.d(s);
  {$ENDIF ANDROID_USB_DEBUG}
  for i := 0 to AUSBDevice.getInterfaceCount - 1 do
  begin
    AUSBInterface := AUSBDevice.getInterface(i);
    {$IFDEF ANDROID_USB_DEBUG}
    Log.d('  ' + JStringToString(AUSBInterface.toString));
    {$ENDIF ANDROID_USB_DEBUG}
    if AUSBInterface.getInterfaceClass = AUSBClass then
    begin
      Result := True;
      Exit;
    end;
  end;
  AUSBInterface := nil;
  Result := False;
end;

class function TUSBDeviceWriter.GetDeviceByName(AUSBDevices: JArrayList;
  const AName: string): JUsbDevice;
var
  LDevicesIterator: JIterator;
  LName: string;
begin
  LDevicesIterator := AUSBDevices.iterator;
  while LDevicesIterator.hasNext do
  begin
    Result := TJUsbDevice.Wrap((LDevicesIterator.next as ILocalObject).GetObjectID);
    LName := JStringToString(Result.getDeviceName);
    if AnsiSameText(LName, AName) then
      Exit;
  end;
  Result := nil;
end;

class function TUSBDeviceWriter.WriteToDevice(
  AUSBDeviceConnection: JUsbDeviceConnection; AUsbEndpoint: JUsbEndpoint;
  ABytes: TBytes): Integer;
var
  LArrayLength: Integer;
  LSize, LBytesWritten: Integer;
  LBytes: TBytes;
  LJBytes: TJavaArray<Byte>;
begin
  Result := 0;
  LArrayLength := Length(ABytes);

  {$IFDEF ANDROID_USB_DEBUG}
  Log.d('USB: Writing %d bytes to a device', [LArrayLength]);
  {$ENDIF ANDROID_USB_DEBUG}
  while (Result < LArrayLength) do
  begin
    LSize := Math.Min(LArrayLength - Result, AUsbEndpoint.getMaxPacketSize);
    LJBytes := TJavaArray<Byte>.Create(LArrayLength);
    try
      LBytes := Copy(ABytes, Result, LSize);
      Move(LBytes[0], LJBytes.Data^, LSize);
      LBytesWritten := AUSBDeviceConnection.bulkTransfer(AUsbEndpoint,
        LJBytes, LJBytes.Length, 10000);
    finally
      FreeAndNil(LJBytes);
    end;
    if LBytesWritten <= 0 then
    begin
      {$IFDEF ANDROID_USB_DEBUG}
      Log.d('USB: None written');
      {$ENDIF ANDROID_USB_DEBUG}
    end;
    Result := Result + LBytesWritten;
  end;
  {$IFDEF ANDROID_USB_DEBUG}
  Log.d('USB: Offset: %d', [Result]);
  {$ENDIF ANDROID_USB_DEBUG}
end;

{ TAndroidUSBPrinter }

class function TAndroidUSBPrinter.Find(
  out AUSBPrinters: JArrayList): Boolean;
begin
  Result := ListDevicesOfClass(TJUsbConstantsUSB_CLASS_PRINTER, AUSBPrinters);
end;

class procedure TAndroidUSBPrinter.Print(APrinter: JUsbDevice;
  const AText: string);
var
  LIntent: JIntent;
  LPermissionIntent: JPendingIntent;
begin
  // set handler
  if not Assigned(FPrintEventHandler) then
    FPrintEventHandler := TPrintEventHandler.Create;
  if not Assigned(__BroadcastReceiver) then
  begin
    __BroadcastReceiver := TBroadcastReceiver.Create(nil);
    __BroadcastReceiver.onReceive := FPrintEventHandler.Received;
    __BroadcastReceiver.RegisterReceive;
  end;
  __BroadcastReceiver.Add(ACTION_USB_PERMISSION);

  LIntent := TJIntent.JavaClass.init(StringToJString(ACTION_USB_PERMISSION));
  LIntent.putExtra(StringToJString(PRINTER_TEXT), StringToJString(AText));
  LPermissionIntent := TJPendingIntent.JavaClass.getBroadcast(
    SharedActivityContext, 0, LIntent, 0);

  {$IFDEF ANDROID_USB_DEBUG}
  Log.d('Requesting permission to device %s', [JStringToString(APrinter.toString)]);
  {$ENDIF ANDROID_USB_DEBUG}
  USBManager.requestPermission(APrinter, LPermissionIntent);
end;

{ TPrintEventHandler }

procedure TPrintEventHandler.Received(AContext: JContext; AIntent: JIntent);
var
  LUsbDevice: JUsbDevice;
  LUsbDeviceConnection: JUsbDeviceConnection;
  LUsbInterface: JUsbInterface;
  LUsbOutEndpoint: JUsbEndpoint;
  s: string;
  sb: TBytes;
begin // FI:C101
  {$IFDEF ANDROID_USB_DEBUG}
  Log.d('Broadcast received: ' + JStringToString(AIntent.getAction));
  {$ENDIF ANDROID_USB_DEBUG}
  if not JStringToString(AIntent.getAction).Equals(TUSBDeviceWriter.ACTION_USB_PERMISSION) then
    Exit;

  LUsbDevice := TJUsbDevice.Wrap((AIntent.getParcelableExtra(TJUsbManager.JavaClass.EXTRA_DEVICE) as ILocalObject).GetObjectID);
  if not AIntent.getBooleanExtra(TJUsbManager.JavaClass.EXTRA_PERMISSION_GRANTED, False) then
  begin
    {$IFDEF ANDROID_USB_DEBUG}
    Log.d('USB: Permission denied for %d', [JStringToString(LUsbDevice.toString)]);
    {$ENDIF ANDROID_USB_DEBUG}
    Exit;
  end;

  if not Assigned(LUsbDevice) then
  begin
    {$IFDEF ANDROID_USB_DEBUG}
    Log.d('USB: NO EXTRA_DEVICE!');
    {$ENDIF ANDROID_USB_DEBUG}
    Exit;
  end;

  {$IFDEF ANDROID_USB_DEBUG}
  Log.d('USB: Using %.4x:%.4x as a USB-printer', [LUsbDevice.getVendorId, LUsbDevice.getProductId]);
  {$ENDIF ANDROID_USB_DEBUG}
  LUsbDeviceConnection := TUSBDeviceWriter.USBManager.openDevice(LUsbDevice);
  try
    {$IFDEF ANDROID_USB_DEBUG}
    Log.d('USB: deviceConnection: %s', [JStringToString(LUsbDeviceConnection.toString)]);
    {$ENDIF ANDROID_USB_DEBUG}
    if TUSBDeviceWriter.FindInterfaceForDevice(LUsbDevice, TJUsbConstantsUSB_CLASS_PRINTER, LUsbInterface) then
    begin
      if not LUsbDeviceConnection.claimInterface(LUsbInterface, True) then
      begin
        {$IFDEF ANDROID_USB_DEBUG}
        Log.d('Cannot claim interface');
        {$ENDIF ANDROID_USB_DEBUG}
        Exit;
      end;
      {$IFDEF ANDROID_USB_DEBUG}
      Log.d('Interface claimed');
      {$ENDIF ANDROID_USB_DEBUG}
      if not TUSBDeviceWriter.FindBulkEndpointForInterface(LUsbInterface, LUsbOutEndpoint) then
      begin
        {$IFDEF ANDROID_USB_DEBUG}
        Log.d('Cannot find out endpoint');
        {$ENDIF ANDROID_USB_DEBUG}
        Exit;
      end
      else
      begin
        s := JStringToString(AIntent.getStringExtra(StringToJString(PRINTER_TEXT)));
        sb := TEncoding.GetEncoding(1251).GetBytes(s);
        {$IFDEF ANDROID_USB_DEBUG}
        Log.d('USB: writing bytes: %s', [BytesToHexStr(sb)]);
        {$ENDIF ANDROID_USB_DEBUG}
        TUSBDeviceWriter.WriteToDevice(LUsbDeviceConnection, LUsbOutEndpoint, sb);
      end;
    end;
  finally
    LUsbDeviceConnection.close;
  end;
end;

initialization
  TAndroidUSBPrinter.FPrintEventHandler := nil;
  __BroadcastReceiver := nil;

finalization
  FreeAndNil(__BroadcastReceiver);
  FreeAndNil(TAndroidUSBPrinter.FPrintEventHandler);
end.
