#include "windows_bluetooth_bridge.h"

#include <flutter/standard_method_codec.h>

#include <chrono>
#include <algorithm>
#include <cctype>
#include <iomanip>
#include <sstream>
#include <string>

#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.Rfcomm.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Networking.Sockets.h>
#include <winrt/Windows.Storage.Streams.h>

namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;
using BluetoothAdapter = winrt::Windows::Devices::Bluetooth::BluetoothAdapter;
using BluetoothLEAdvertisementWatcher =
    winrt::Windows::Devices::Bluetooth::Advertisement::
        BluetoothLEAdvertisementWatcher;
using BluetoothLEAdvertisementReceivedEventArgs =
    winrt::Windows::Devices::Bluetooth::Advertisement::
        BluetoothLEAdvertisementReceivedEventArgs;
using BluetoothLEScanningMode =
    winrt::Windows::Devices::Bluetooth::Advertisement::
        BluetoothLEScanningMode;
using RadioState = winrt::Windows::Devices::Radios::RadioState;
using BluetoothCacheMode =
    winrt::Windows::Devices::Bluetooth::BluetoothCacheMode;
using BluetoothLEDevice =
    winrt::Windows::Devices::Bluetooth::BluetoothLEDevice;
using GattCharacteristic =
    winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
        GattCharacteristic;
using GattClientCharacteristicConfigurationDescriptorValue =
    winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
        GattClientCharacteristicConfigurationDescriptorValue;
using GattCommunicationStatus =
    winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
        GattCommunicationStatus;
using GattWriteOption =
    winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
        GattWriteOption;
using DataReader = winrt::Windows::Storage::Streams::DataReader;
using DataWriter = winrt::Windows::Storage::Streams::DataWriter;
using BluetoothDevice = winrt::Windows::Devices::Bluetooth::BluetoothDevice;
using RfcommDeviceService =
    winrt::Windows::Devices::Bluetooth::Rfcomm::RfcommDeviceService;
using RfcommServiceId =
    winrt::Windows::Devices::Bluetooth::Rfcomm::RfcommServiceId;
using RfcommServiceProvider =
    winrt::Windows::Devices::Bluetooth::Rfcomm::RfcommServiceProvider;
using DeviceInformation =
    winrt::Windows::Devices::Enumeration::DeviceInformation;
using DeviceInformationKind =
    winrt::Windows::Devices::Enumeration::DeviceInformationKind;
using StreamSocket = winrt::Windows::Networking::Sockets::StreamSocket;
using StreamSocketListener =
    winrt::Windows::Networking::Sockets::StreamSocketListener;

std::string Address(uint64_t value) {
  std::ostringstream output;
  output << std::uppercase << std::hex << std::setfill('0');
  for (int shift = 40; shift >= 0; shift -= 8) {
    if (shift != 40) output << ':';
    output << std::setw(2) << ((value >> shift) & 0xff);
  }
  return output.str();
}

int64_t NowMillis() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::system_clock::now().time_since_epoch())
      .count();
}

EncodableValue Value(std::string value) {
  return EncodableValue(std::move(value));
}

const EncodableValue* Argument(const EncodableMap& arguments,
                               const std::string& name) {
  const auto iterator = arguments.find(Value(name));
  return iterator == arguments.end() ? nullptr : &iterator->second;
}

std::string StringArgument(const EncodableMap& arguments,
                           const std::string& name) {
  const auto value = Argument(arguments, name);
  if (value == nullptr) return {};
  const auto text = std::get_if<std::string>(value);
  return text == nullptr ? std::string{} : *text;
}

std::string Uuid(winrt::guid value) {
  auto text = winrt::to_string(winrt::to_hstring(value));
  std::transform(text.begin(), text.end(), text.begin(),
                 [](unsigned char character) {
                   return static_cast<char>(std::tolower(character));
                 });
  return text;
}

uint64_t ParseAddress(std::string value) {
  value.erase(std::remove_if(value.begin(), value.end(),
                             [](unsigned char character) {
                               return character == ':' || character == '-';
                             }),
              value.end());
  if (value.empty()) throw std::invalid_argument("Bluetooth address is empty");
  return std::stoull(value, nullptr, 16);
}

std::vector<uint8_t> ReadBuffer(
    winrt::Windows::Storage::Streams::IBuffer const& buffer) {
  auto reader = DataReader::FromBuffer(buffer);
  std::vector<uint8_t> bytes(reader.UnconsumedBufferLength());
  reader.ReadBytes(bytes);
  return bytes;
}
}  // namespace

WindowsBluetoothBridge::WindowsBluetoothBridge(
    flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "nettools/native",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        try {
          const std::string& method = call.method_name();
          if (method == "bluetoothStatus") {
            result->Success(EncodableValue(Status()));
          } else if (method == "bluetoothBonded") {
            result->Success(EncodableValue(BondedDevices()));
          } else if (method == "classicScanStart") {
            StartClassicScan();
            result->Success();
          } else if (method == "classicScanStop") {
            StopClassicScan();
            result->Success();
          } else if (method == "classicConnect") {
            ConnectClassic(std::get<EncodableMap>(*call.arguments()));
            result->Success();
          } else if (method == "classicServerStart") {
            StartClassicServer(std::get<EncodableMap>(*call.arguments()));
            result->Success();
          } else if (method == "classicSend") {
            SendClassic(std::get<EncodableMap>(*call.arguments()));
            result->Success();
          } else if (method == "classicStop") {
            StopClassic();
            result->Success();
          } else if (method == "bleScanStart") {
            StartBleScan();
            result->Success();
          } else if (method == "bleScanStop") {
            StopBleScan();
            result->Success();
          } else if (method == "bluetoothPollEvent") {
            std::lock_guard<std::mutex> lock(mutex_);
            if (events_.empty()) {
              result->Success();
            } else {
              auto event = std::move(events_.front());
              events_.pop();
              result->Success(EncodableValue(std::move(event)));
            }
          } else if (method == "bleConnect") {
            ConnectBle(std::get<EncodableMap>(*call.arguments()));
            result->Success();
          } else if (method == "bleDisconnect") {
            DisconnectBle();
            result->Success();
          } else if (method == "bleRead") {
            result->Success(EncodableValue(
                ReadBle(std::get<EncodableMap>(*call.arguments()))));
          } else if (method == "bleWrite") {
            result->Success(EncodableValue(
                WriteBle(std::get<EncodableMap>(*call.arguments()))));
          } else if (method == "bleNotify") {
            result->Success(EncodableValue(
                NotifyBle(std::get<EncodableMap>(*call.arguments()))));
          } else if (method == "bleServerStart") {
            StartBleServer(std::get<EncodableMap>(*call.arguments()));
            result->Success();
          } else if (method == "bleServerStop") {
            StopBleServer();
            result->Success();
          } else if (method == "bleServerNotify") {
            result->Success(EncodableValue(
                NotifyBleServer(std::get<EncodableMap>(*call.arguments()))));
          } else {
            result->NotImplemented();
          }
        } catch (const winrt::hresult_error& error) {
          result->Error("bluetooth.winrtFailure",
                        winrt::to_string(error.message()));
        } catch (const std::exception& error) {
          result->Error("bluetooth.nativeFailure", error.what());
        }
      });
}

WindowsBluetoothBridge::~WindowsBluetoothBridge() {
  StopClassicScan();
  StopClassic();
  StopBleServer();
  StopBleScan();
  DisconnectBle();
}

EncodableMap WindowsBluetoothBridge::Status() {
  auto adapter = BluetoothAdapter::GetDefaultAsync().get();
  if (!adapter) {
    return {{Value("supported"), EncodableValue(false)},
            {Value("enabled"), EncodableValue(false)},
            {Value("errorCode"), Value("bluetooth.adapterMissing")},
            {Value("technicalDetails"),
             Value("Windows did not expose a Bluetooth adapter")}};
  }
  bool enabled = true;
  try {
    auto radio = adapter.GetRadioAsync().get();
    enabled = radio && radio.State() == RadioState::On;
  } catch (...) {
    // Some enterprise policies deny radio state access while scans still work.
  }
  return {
      {Value("supported"), EncodableValue(true)},
      {Value("enabled"), EncodableValue(enabled)},
      {Value("platform"), Value("windows")},
      {Value("classic"), EncodableValue(true)},
      {Value("address"), Value(Address(adapter.BluetoothAddress()))},
      {Value("ble"), EncodableValue(adapter.IsLowEnergySupported())},
      {Value("advertising"),
       EncodableValue(adapter.IsPeripheralRoleSupported())},
      {Value("extendedAdvertising"), EncodableValue(false)},
      {Value("permissions"),
       EncodableValue(EncodableMap{
           {Value("scan"), EncodableValue(true)},
           {Value("connect"), EncodableValue(true)},
           {Value("advertise"),
            EncodableValue(adapter.IsPeripheralRoleSupported())},
       })},
  };
}

flutter::EncodableList WindowsBluetoothBridge::BondedDevices() {
  flutter::EncodableList rows;
  const auto selector = BluetoothDevice::GetDeviceSelectorFromPairingState(true);
  const auto devices = DeviceInformation::FindAllAsync(selector).get();
  for (const auto& information : devices) {
    try {
      const auto device = BluetoothDevice::FromIdAsync(information.Id()).get();
      if (!device) continue;
      rows.push_back(EncodableValue(EncodableMap{
          {Value("address"), Value(Address(device.BluetoothAddress()))},
          {Value("name"), Value(winrt::to_string(information.Name()))},
          {Value("localName"), Value(winrt::to_string(information.Name()))},
          {Value("bonded"), EncodableValue(true)},
          {Value("bondState"), EncodableValue(int32_t{12})},
          {Value("connected"),
           EncodableValue(device.ConnectionStatus() ==
                           winrt::Windows::Devices::Bluetooth::
                               BluetoothConnectionStatus::Connected)},
          {Value("connectable"), EncodableValue(true)},
          {Value("services"), EncodableValue(flutter::EncodableList{})},
          {Value("seenAt"), EncodableValue(NowMillis())},
      }));
    } catch (...) {
      // A device may disappear while Windows resolves its association endpoint.
    }
  }
  return rows;
}

void WindowsBluetoothBridge::StartClassicScan() {
  StopClassicScan();
  classic_watcher_ =
      DeviceInformation::CreateWatcher(BluetoothDevice::GetDeviceSelector());
  classic_added_token_ = classic_watcher_.Added(
      [this](auto const&, DeviceInformation const& information) {
        try {
          const auto device =
              BluetoothDevice::FromIdAsync(information.Id()).get();
          if (!device) return;
          Enqueue({
              {Value("type"), Value("classicDevice")},
              {Value("time"), EncodableValue(NowMillis())},
              {Value("seenAt"), EncodableValue(NowMillis())},
              {Value("address"), Value(Address(device.BluetoothAddress()))},
              {Value("name"), Value(winrt::to_string(information.Name()))},
              {Value("localName"),
               Value(winrt::to_string(information.Name()))},
              {Value("bonded"),
               EncodableValue(information.Pairing().IsPaired())},
              {Value("bondState"), EncodableValue(
                   information.Pairing().IsPaired() ? int32_t{12}
                                                    : int32_t{10})},
              {Value("connected"),
               EncodableValue(device.ConnectionStatus() ==
                               winrt::Windows::Devices::Bluetooth::
                                   BluetoothConnectionStatus::Connected)},
              {Value("connectable"), EncodableValue(true)},
              {Value("services"), EncodableValue(flutter::EncodableList{})},
          });
        } catch (...) {
          // Keep discovery alive when a transient device can no longer resolve.
        }
      });
  classic_stopped_token_ = classic_watcher_.Stopped(
      [this](auto const&, auto const&) {
        Enqueue({{Value("type"), Value("classicScan")},
                 {Value("time"), EncodableValue(NowMillis())},
                 {Value("state"), Value("stopped")}});
      });
  classic_watcher_.Start();
  Enqueue({{Value("type"), Value("classicScan")},
           {Value("time"), EncodableValue(NowMillis())},
           {Value("state"), Value("started")}});
}

void WindowsBluetoothBridge::StopClassicScan() {
  if (!classic_watcher_) return;
  try {
    classic_watcher_.Stop();
    classic_watcher_.Added(classic_added_token_);
    classic_watcher_.Stopped(classic_stopped_token_);
  } catch (...) {
  }
  classic_watcher_ = nullptr;
}

void WindowsBluetoothBridge::ConnectClassic(
    const EncodableMap& arguments) {
  StopClassic();
  const auto address_text = StringArgument(arguments, "address");
  const auto uuid_text = StringArgument(arguments, "uuid");
  Enqueue({{Value("type"), Value("classicConnection")},
           {Value("time"), EncodableValue(NowMillis())},
           {Value("state"), Value("connecting")},
           {Value("peer"), Value(address_text)},
           {Value("uuid"), Value(uuid_text)}});
  classic_device_ =
      BluetoothDevice::FromBluetoothAddressAsync(ParseAddress(address_text))
          .get();
  if (!classic_device_) {
    throw std::runtime_error("Classic Bluetooth device is unavailable");
  }
  const auto service_id = RfcommServiceId::FromUuid(winrt::guid{uuid_text});
  const auto result = classic_device_
                          .GetRfcommServicesForIdAsync(
                              service_id, BluetoothCacheMode::Uncached)
                          .get();
  if (result.Services().Size() == 0) {
    throw std::runtime_error("The requested RFCOMM service was not found");
  }
  rfcomm_service_ = result.Services().GetAt(0);
  StreamSocket socket;
  socket.ConnectAsync(rfcomm_service_.ConnectionHostName(),
                      rfcomm_service_.ConnectionServiceName())
      .get();
  AttachClassicSocket(socket, address_text);
}

void WindowsBluetoothBridge::StartClassicServer(
    const EncodableMap& arguments) {
  StopClassic();
  const auto name = StringArgument(arguments, "name");
  const auto uuid_text = StringArgument(arguments, "uuid");
  const auto service_id = RfcommServiceId::FromUuid(winrt::guid{uuid_text});
  rfcomm_provider_ = RfcommServiceProvider::CreateAsync(service_id).get();
  classic_listener_ = StreamSocketListener();
  classic_connection_token_ = classic_listener_.ConnectionReceived(
      [this](StreamSocketListener const&, auto const& arguments) {
        AttachClassicSocket(arguments.Socket(), "incoming");
      });
  classic_listener_.BindServiceNameAsync(service_id.AsString()).get();
  rfcomm_provider_.StartAdvertising(classic_listener_, true);
  Enqueue({{Value("type"), Value("classicServer")},
           {Value("time"), EncodableValue(NowMillis())},
           {Value("state"), Value("listening")},
           {Value("name"), Value(name)},
           {Value("uuid"), Value(uuid_text)}});
}

void WindowsBluetoothBridge::AttachClassicSocket(StreamSocket socket,
                                                  const std::string& peer) {
  classic_reading_ = false;
  try {
    if (classic_socket_) classic_socket_.Close();
  } catch (...) {
  }
  if (classic_reader_thread_.joinable() &&
      classic_reader_thread_.get_id() != std::this_thread::get_id()) {
    classic_reader_thread_.join();
  }
  classic_socket_ = socket;
  classic_reader_ = DataReader(socket.InputStream());
  classic_reader_.InputStreamOptions(
      winrt::Windows::Storage::Streams::InputStreamOptions::Partial);
  classic_writer_ = DataWriter(socket.OutputStream());
  classic_reading_ = true;
  Enqueue({{Value("type"), Value("classicConnection")},
           {Value("time"), EncodableValue(NowMillis())},
           {Value("state"), Value("connected")},
           {Value("peer"), Value(peer)},
           {Value("status"), EncodableValue(int32_t{0})}});
  classic_reader_thread_ = std::thread([this]() { ReadClassicLoop(); });
}

void WindowsBluetoothBridge::ReadClassicLoop() {
  winrt::init_apartment(winrt::apartment_type::multi_threaded);
  try {
    while (classic_reading_ && classic_reader_) {
      const auto loaded = classic_reader_.LoadAsync(4096).get();
      if (loaded == 0) break;
      std::vector<uint8_t> bytes(loaded);
      classic_reader_.ReadBytes(bytes);
      Enqueue({{Value("type"), Value("data")},
               {Value("time"), EncodableValue(NowMillis())},
               {Value("transport"), Value("Classic")},
               {Value("direction"), Value("RX")},
               {Value("operation"), Value("stream")},
               {Value("bytes"), EncodableValue(std::move(bytes))}});
    }
  } catch (const std::exception& error) {
    if (classic_reading_) {
      Enqueue({{Value("type"), Value("classicConnection")},
               {Value("time"), EncodableValue(NowMillis())},
               {Value("state"), Value("error")},
               {Value("errorCode"), Value("bluetooth.rfcommReadFailed")},
               {Value("technicalDetails"), Value(error.what())}});
    }
  }
  classic_reading_ = false;
  Enqueue({{Value("type"), Value("classicConnection")},
           {Value("time"), EncodableValue(NowMillis())},
           {Value("state"), Value("disconnected")},
           {Value("status"), EncodableValue(int32_t{0})}});
}

void WindowsBluetoothBridge::SendClassic(const EncodableMap& arguments) {
  if (!classic_writer_) {
    throw std::runtime_error("RFCOMM is not connected");
  }
  const auto encoded = Argument(arguments, "bytes");
  const auto bytes = encoded == nullptr
                         ? nullptr
                         : std::get_if<std::vector<uint8_t>>(encoded);
  if (bytes == nullptr) throw std::invalid_argument("RFCOMM payload is missing");
  classic_writer_.WriteBytes(*bytes);
  classic_writer_.StoreAsync().get();
  Enqueue({{Value("type"), Value("data")},
           {Value("time"), EncodableValue(NowMillis())},
           {Value("transport"), Value("Classic")},
           {Value("direction"), Value("TX")},
           {Value("operation"), Value("write")},
           {Value("bytes"), EncodableValue(*bytes)}});
}

void WindowsBluetoothBridge::StopClassic() {
  classic_reading_ = false;
  try {
    if (rfcomm_provider_) rfcomm_provider_.StopAdvertising();
    if (classic_listener_) {
      classic_listener_.ConnectionReceived(classic_connection_token_);
      classic_listener_.Close();
    }
    if (classic_reader_) classic_reader_.Close();
    if (classic_writer_) classic_writer_.Close();
    if (classic_socket_) classic_socket_.Close();
  } catch (...) {
  }
  if (classic_reader_thread_.joinable() &&
      classic_reader_thread_.get_id() != std::this_thread::get_id()) {
    classic_reader_thread_.join();
  }
  classic_reader_ = nullptr;
  classic_writer_ = nullptr;
  classic_socket_ = nullptr;
  classic_listener_ = nullptr;
  rfcomm_provider_ = nullptr;
  if (rfcomm_service_) rfcomm_service_.Close();
  rfcomm_service_ = nullptr;
  if (classic_device_) classic_device_.Close();
  classic_device_ = nullptr;
}

void WindowsBluetoothBridge::StartBleScan() {
  StopBleScan();
  watcher_ = BluetoothLEAdvertisementWatcher();
  watcher_.ScanningMode(BluetoothLEScanningMode::Active);
  received_token_ = watcher_.Received(
      [this](BluetoothLEAdvertisementWatcher const&,
             BluetoothLEAdvertisementReceivedEventArgs const& args) {
        const auto advertisement = args.Advertisement();
        EncodableMap event{
            {Value("type"), Value("bleDevice")},
            {Value("time"), EncodableValue(NowMillis())},
            {Value("seenAt"), EncodableValue(NowMillis())},
            {Value("address"), Value(Address(args.BluetoothAddress()))},
            {Value("rssi"),
             EncodableValue(static_cast<int32_t>(
                 args.RawSignalStrengthInDBm()))},
            {Value("localName"),
             Value(winrt::to_string(advertisement.LocalName()))},
            {Value("connectable"), EncodableValue(true)},
        };
        Enqueue(std::move(event));
      });
  watcher_.Start();
  Enqueue({{Value("type"), Value("bleScan")},
           {Value("time"), EncodableValue(NowMillis())},
           {Value("state"), Value("started")}});
}

void WindowsBluetoothBridge::StopBleScan() {
  if (!watcher_) return;
  try {
    watcher_.Stop();
    watcher_.Received(received_token_);
  } catch (...) {
  }
  watcher_ = nullptr;
}

void WindowsBluetoothBridge::ConnectBle(const EncodableMap& arguments) {
  DisconnectBle();
  const auto address_text = StringArgument(arguments, "address");
  Enqueue({{Value("type"), Value("bleConnection")},
           {Value("time"), EncodableValue(NowMillis())},
           {Value("state"), Value("connecting")},
           {Value("peer"), Value(address_text)}});
  device_ = BluetoothLEDevice::FromBluetoothAddressAsync(
                ParseAddress(address_text))
                .get();
  if (!device_) throw std::runtime_error("BLE device is unavailable");
  auto services_result =
      device_.GetGattServicesAsync(BluetoothCacheMode::Uncached).get();
  if (services_result.Status() != GattCommunicationStatus::Success) {
    throw std::runtime_error("GATT service discovery failed");
  }
  flutter::EncodableList service_rows;
  for (const auto& service : services_result.Services()) {
    flutter::EncodableList characteristic_rows;
    auto characteristics_result =
        service.GetCharacteristicsAsync(BluetoothCacheMode::Uncached).get();
    if (characteristics_result.Status() == GattCommunicationStatus::Success) {
      for (const auto& characteristic : characteristics_result.Characteristics()) {
        const auto id = Uuid(characteristic.Uuid());
        // C++/WinRT interface wrappers deliberately have no default
        // constructor. std::map::operator[] would try to default-construct a
        // GattCharacteristic before assigning it, which fails with MSVC
        // C2512. Insert or replace the projected object directly instead.
        characteristics_.insert_or_assign(id, characteristic);
        characteristic_rows.push_back(EncodableValue(EncodableMap{
            {Value("uuid"), Value(id)},
            {Value("properties"),
             EncodableValue(static_cast<int32_t>(
                 characteristic.CharacteristicProperties()))},
            {Value("permissions"), EncodableValue(int32_t{0})},
            {Value("descriptors"), EncodableValue(flutter::EncodableList{})},
        }));
      }
    }
    service_rows.push_back(EncodableValue(EncodableMap{
        {Value("uuid"), Value(Uuid(service.Uuid()))},
        {Value("type"), EncodableValue(int32_t{0})},
        {Value("characteristics"), EncodableValue(characteristic_rows)},
    }));
  }
  Enqueue({{Value("type"), Value("bleConnection")},
           {Value("time"), EncodableValue(NowMillis())},
           {Value("state"), Value("connected")},
           {Value("peer"), Value(address_text)},
           {Value("status"), EncodableValue(int32_t{0})}});
  Enqueue({{Value("type"), Value("bleServices")},
           {Value("time"), EncodableValue(NowMillis())},
           {Value("status"), EncodableValue(int32_t{0})},
           {Value("services"), EncodableValue(service_rows)}});
}

void WindowsBluetoothBridge::DisconnectBle() {
  for (const auto& registration : notification_tokens_) {
    try {
      registration.first.ValueChanged(registration.second);
    } catch (...) {
    }
  }
  notification_tokens_.clear();
  characteristics_.clear();
  if (device_) device_.Close();
  device_ = nullptr;
}

bool WindowsBluetoothBridge::ReadBle(const EncodableMap& arguments) {
  const auto id = StringArgument(arguments, "characteristic");
  const auto iterator = characteristics_.find(id);
  if (iterator == characteristics_.end()) {
    throw std::runtime_error("GATT characteristic was not discovered");
  }
  const auto result =
      iterator->second.ReadValueAsync(BluetoothCacheMode::Uncached).get();
  if (result.Status() != GattCommunicationStatus::Success) return false;
  Enqueue({{Value("type"), Value("data")},
           {Value("time"), EncodableValue(NowMillis())},
           {Value("transport"), Value("BLE")},
           {Value("direction"), Value("RX")},
           {Value("operation"), Value("read")},
           {Value("status"), EncodableValue(int32_t{0})},
           {Value("characteristic"), Value(id)},
           {Value("bytes"), EncodableValue(ReadBuffer(result.Value()))}});
  return true;
}

bool WindowsBluetoothBridge::WriteBle(const EncodableMap& arguments) {
  const auto id = StringArgument(arguments, "characteristic");
  const auto iterator = characteristics_.find(id);
  if (iterator == characteristics_.end()) {
    throw std::runtime_error("GATT characteristic was not discovered");
  }
  const auto encoded = Argument(arguments, "bytes");
  const auto bytes = encoded == nullptr
                         ? nullptr
                         : std::get_if<std::vector<uint8_t>>(encoded);
  if (bytes == nullptr) throw std::invalid_argument("BLE payload is missing");
  auto writer = DataWriter();
  writer.WriteBytes(*bytes);
  const bool with_response = [&]() {
    const auto value = Argument(arguments, "withResponse");
    const auto boolean = value == nullptr ? nullptr : std::get_if<bool>(value);
    return boolean == nullptr || *boolean;
  }();
  const auto status = iterator->second
                          .WriteValueAsync(
                              writer.DetachBuffer(),
                              with_response ? GattWriteOption::WriteWithResponse
                                            : GattWriteOption::WriteWithoutResponse)
                          .get();
  return status == GattCommunicationStatus::Success;
}

bool WindowsBluetoothBridge::NotifyBle(const EncodableMap& arguments) {
  const auto id = StringArgument(arguments, "characteristic");
  const auto iterator = characteristics_.find(id);
  if (iterator == characteristics_.end()) {
    throw std::runtime_error("GATT characteristic was not discovered");
  }
  const auto encoded = Argument(arguments, "enable");
  const auto enabled = encoded == nullptr ? nullptr : std::get_if<bool>(encoded);
  if (enabled == nullptr) throw std::invalid_argument("Notify state is missing");
  auto characteristic = iterator->second;
  if (*enabled) {
    auto token = characteristic.ValueChanged(
        [this, id](GattCharacteristic const&,
                   auto const& event) {
          Enqueue({{Value("type"), Value("data")},
                   {Value("time"), EncodableValue(NowMillis())},
                   {Value("transport"), Value("BLE")},
                   {Value("direction"), Value("RX")},
                   {Value("operation"), Value("notify")},
                   {Value("characteristic"), Value(id)},
                   {Value("bytes"),
                    EncodableValue(ReadBuffer(event.CharacteristicValue()))}});
        });
    notification_tokens_.push_back({characteristic, token});
  }
  const auto status = characteristic
                          .WriteClientCharacteristicConfigurationDescriptorAsync(
                              *enabled
                                  ? GattClientCharacteristicConfigurationDescriptorValue::Notify
                                  : GattClientCharacteristicConfigurationDescriptorValue::None)
                          .get();
  return status == GattCommunicationStatus::Success;
}

void WindowsBluetoothBridge::StartBleServer(
    const EncodableMap& arguments) {
  StopBleServer();
  const auto service_text = StringArgument(arguments, "service");
  const auto characteristic_text =
      StringArgument(arguments, "characteristic");
  const auto service_result =
      winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
          GattServiceProvider::CreateAsync(winrt::guid{service_text})
              .get();
  if (service_result.Error() !=
      winrt::Windows::Devices::Bluetooth::BluetoothError::Success) {
    throw std::runtime_error("Unable to create the local GATT service");
  }
  gatt_provider_ = service_result.ServiceProvider();
  winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
      GattLocalCharacteristicParameters parameters;
  parameters.CharacteristicProperties(
      winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
          GattCharacteristicProperties::Read |
      winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
          GattCharacteristicProperties::Write |
      winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
          GattCharacteristicProperties::WriteWithoutResponse |
      winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
          GattCharacteristicProperties::Notify);
  parameters.ReadProtectionLevel(
      winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
          GattProtectionLevel::Plain);
  parameters.WriteProtectionLevel(
      winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
          GattProtectionLevel::Plain);
  parameters.UserDescription(L"ProtoDeck data channel");
  const auto characteristic_result =
      gatt_provider_.Service()
          .CreateCharacteristicAsync(winrt::guid{characteristic_text},
                                     parameters)
          .get();
  if (characteristic_result.Error() !=
      winrt::Windows::Devices::Bluetooth::BluetoothError::Success) {
    StopBleServer();
    throw std::runtime_error("Unable to create the local GATT characteristic");
  }
  gatt_local_characteristic_ = characteristic_result.Characteristic();
  gatt_read_token_ = gatt_local_characteristic_.ReadRequested(
      [this](auto const&, auto const& arguments) {
        const auto deferral = arguments.GetDeferral();
        try {
          const auto request = arguments.GetRequestAsync().get();
          if (request) {
            DataWriter writer;
            {
              std::lock_guard<std::mutex> lock(mutex_);
              writer.WriteBytes(gatt_server_value_);
            }
            request.RespondWithValue(writer.DetachBuffer());
          }
        } catch (...) {
        }
        deferral.Complete();
      });
  gatt_write_token_ = gatt_local_characteristic_.WriteRequested(
      [this, characteristic_text](auto const&, auto const& arguments) {
        const auto deferral = arguments.GetDeferral();
        try {
          const auto request = arguments.GetRequestAsync().get();
          if (request) {
            const auto bytes = ReadBuffer(request.Value());
            {
              std::lock_guard<std::mutex> lock(mutex_);
              gatt_server_value_ = bytes;
            }
            Enqueue({{Value("type"), Value("data")},
                     {Value("time"), EncodableValue(NowMillis())},
                     {Value("transport"), Value("BLE Server")},
                     {Value("direction"), Value("RX")},
                     {Value("operation"), Value("write")},
                     {Value("characteristic"), Value(characteristic_text)},
                     {Value("bytes"), EncodableValue(bytes)}});
            request.Respond();
          }
        } catch (...) {
        }
        deferral.Complete();
      });
  const auto advertise = [&]() {
    const auto value = Argument(arguments, "advertise");
    const auto boolean = value == nullptr ? nullptr : std::get_if<bool>(value);
    return boolean == nullptr || *boolean;
  }();
  if (advertise) {
    winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
        GattServiceProviderAdvertisingParameters advertising;
    advertising.IsConnectable(true);
    advertising.IsDiscoverable(true);
    gatt_provider_.StartAdvertising(advertising);
  }
  Enqueue({{Value("type"), Value("bleServer")},
           {Value("time"), EncodableValue(NowMillis())},
           {Value("state"), Value("started")},
           {Value("service"), Value(service_text)},
           {Value("characteristic"), Value(characteristic_text)}});
}

void WindowsBluetoothBridge::StopBleServer() {
  try {
    if (gatt_provider_) gatt_provider_.StopAdvertising();
    if (gatt_local_characteristic_) {
      gatt_local_characteristic_.ReadRequested(gatt_read_token_);
      gatt_local_characteristic_.WriteRequested(gatt_write_token_);
    }
  } catch (...) {
  }
  gatt_local_characteristic_ = nullptr;
  gatt_provider_ = nullptr;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    gatt_server_value_.clear();
  }
}

int WindowsBluetoothBridge::NotifyBleServer(
    const EncodableMap& arguments) {
  if (!gatt_local_characteristic_) {
    throw std::runtime_error("The local GATT server is not running");
  }
  const auto encoded = Argument(arguments, "bytes");
  const auto bytes = encoded == nullptr
                         ? nullptr
                         : std::get_if<std::vector<uint8_t>>(encoded);
  if (bytes == nullptr) throw std::invalid_argument("GATT payload is missing");
  DataWriter writer;
  writer.WriteBytes(*bytes);
  const auto results =
      gatt_local_characteristic_.NotifyValueAsync(writer.DetachBuffer()).get();
  {
    std::lock_guard<std::mutex> lock(mutex_);
    gatt_server_value_ = *bytes;
  }
  Enqueue({{Value("type"), Value("data")},
           {Value("time"), EncodableValue(NowMillis())},
           {Value("transport"), Value("BLE Server")},
           {Value("direction"), Value("TX")},
           {Value("operation"), Value("notify")},
           {Value("bytes"), EncodableValue(*bytes)}});
  return static_cast<int>(results.Size());
}

void WindowsBluetoothBridge::Enqueue(EncodableMap value) {
  std::lock_guard<std::mutex> lock(mutex_);
  events_.push(std::move(value));
  while (events_.size() > 1000) events_.pop();
}
