unit Android.USB;

interface

uses
  Classes, SysUtils,
  Androidapi.JNI.JavaTypes,
  android.hardware.usb.UsbConstants,
  android.hardware.usb.UsbDevice,
  android.hardware.usb.UsbInterface,
  android.hardware.usb.UsbManager;

type
  TUSBDeviceEnumerator = class
  protected
    class function USBManager: JUsbManager;
    class function ClassMatchesSeekingClass(ADeviceClass, ASeekingClass: Integer): Boolean;
    class function GetDeviceByName(AUSBDevices: JArrayList;
      const AName: string): JUsbDevice;
    class function FindInterfaceOfClassForDevice(AUSBDevice: JUSBDevice;
      AUSBClass: Integer;
      out AUSBInterface: JUSBInterface): Boolean;
  public
    const
      DEVICE_CLASS_ANY = $FF;
    class function ListDevicesOfClass(AUSBClass: Integer;
      out AUSBDevices: JArrayList): Boolean;
  end;

  TListUsbDevicesMethod = reference to procedure (AList: TStrings;
      const AUsbDeviceBusPath: string;
      const AVendorID, AProductID: Integer);

  TUSBDevicesAndroid = class(TUSBDeviceEnumerator)
  protected
  public
    class function ListAvailableAsCSV(ADeviceClass: Integer;
      AListUsbDevicesMethod: TListUsbDevicesMethod): string;
  end;

implementation

uses
  FMX.Types,
  Androidapi.Helpers, Androidapi.JNIBridge,
  Androidapi.Jni,
  Androidapi.JNI.GraphicsContentViewText;

{ TUSBDeviceEnumerator }

class function TUSBDeviceEnumerator.ListDevicesOfClass(AUSBClass: Integer;
  out AUSBDevices: JArrayList): Boolean;
var
  LUsbManager: JUsbManager;
  LUsbDevice: JUsbDevice;
  LUsbDevicesIterator: JIterator;
  LUsbDeviceInterface: JUsbInterface;
  {$IFDEF ANDROID_USB_DEBUG}
  s: string;
  {$ENDIF ANDROID_USB_DEBUG}
begin
  LUsbManager := USBManager;
  LUsbDevicesIterator := LUsbManager.getDeviceList.values.iterator;
  AUSBDevices := TJArrayList.Create;
  while LUsbDevicesIterator.hasNext do
  begin
    LUsbDevice := TJUsbDevice.Wrap((LUsbDevicesIterator.next as ILocalObject).GetObjectID);
    {$IFDEF ANDROID_USB_DEBUG}
    s := Format('USB device: name: %s; class: %d; subclass: %d; ID: %x; VID/PID: %.4x:%.4x',
      [JStringToString(LUsbDevice.getDeviceName), LUsbDevice.getDeviceClass, LUsbDevice.getDeviceSubclass, LUsbDevice.getDeviceId,
      LUsbDevice.getVendorId, LUsbDevice.getProductId]);
    Log.d(s);
    {$ENDIF ANDROID_USB_DEBUG}
    if ClassMatchesSeekingClass(LUsbDevice.getDeviceClass, AUSBClass) then
      AUSBDevices.add(LUsbDevice)
    else if FindInterfaceOfClassForDevice(LUsbDevice, AUSBClass, LUsbDeviceInterface) then
      AUSBDevices.add(LUsbDevice);
  end;
  Result := not AUSBDevices.isEmpty;
  {$IFDEF ANDROID_USB_DEBUG}
  if not Result then
    Log.d('No USB devices found');
  {$ENDIF ANDROID_USB_DEBUG}
end;

class function TUSBDeviceEnumerator.ClassMatchesSeekingClass(ADeviceClass,
  ASeekingClass: Integer): Boolean;
begin
  Result := (ASeekingClass = DEVICE_CLASS_ANY) or (ADeviceClass = ASeekingClass);
end;

class function TUSBDeviceEnumerator.FindInterfaceOfClassForDevice(
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
    if ClassMatchesSeekingClass(AUSBInterface.getInterfaceClass, AUSBClass) then
    begin
      Result := True;
      Exit;
    end;
  end;
  AUSBInterface := nil;
  Result := False;
end;

class function TUSBDeviceEnumerator.GetDeviceByName(AUSBDevices: JArrayList;
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

class function TUSBDeviceEnumerator.USBManager: JUsbManager;
begin
  Result := TJUsbManager.Wrap(SharedActivityContext.getSystemService(TJContext.JavaClass.USB_SERVICE));
end;

class function TUSBDevicesAndroid.ListAvailableAsCSV(ADeviceClass: Integer;
  AListUsbDevicesMethod: TListUsbDevicesMethod): string;
var
  LUsbDevices: JArrayList;
  LusbDeviceIterator: JIterator;
  LUsbDevice: JUsbDevice;
  LName: string;
  AList: TStrings;
begin
  Result := EmptyStr;
  if TUSBDeviceEnumerator.ListDevicesOfClass(ADeviceClass, LUsbDevices) then
  begin
    AList := TStringList.Create;
    try
      LusbDeviceIterator := LUsbDevices.iterator;
      while LusbDeviceIterator.hasNext do
      begin
        LUsbDevice := TJUsbDevice.Wrap((LusbDeviceIterator.next as ILocalObject).GetObjectID);
        LName := JStringToString(LUsbDevice.getDeviceName);
        AListUsbDevicesMethod(AList, LName, LUsbDevice.getVendorId, LUsbDevice.getProductId);
      end;
    finally
      Result := AList.CommaText;
    end;
  end;
end;

end.
