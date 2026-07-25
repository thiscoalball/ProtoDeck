#ifndef RUNNER_WINDOWS_BLUETOOTH_BRIDGE_H_
#define RUNNER_WINDOWS_BLUETOOTH_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>
#include <atomic>
#include <map>
#include <mutex>
#include <queue>
#include <string>
#include <thread>
#include <vector>

// C++/WinRT namespace headers only forward-declare some generic Foundation
// consumers. Include their definitions before any Bluetooth API headers so
// synchronous waits such as IAsyncOperation<T>::get() are available to newer
// MSVC toolchains (otherwise MSVC emits C3779 at the first .get() call).
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Bluetooth.Rfcomm.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Networking.Sockets.h>
#include <winrt/Windows.Storage.Streams.h>

class WindowsBluetoothBridge {
 public:
  explicit WindowsBluetoothBridge(flutter::BinaryMessenger* messenger);
  ~WindowsBluetoothBridge();

 private:
  using AdvertisementWatcher =
      winrt::Windows::Devices::Bluetooth::Advertisement::
          BluetoothLEAdvertisementWatcher;

  flutter::EncodableMap Status();
  flutter::EncodableList BondedDevices();
  void StartBleScan();
  void StopBleScan();
  void ConnectBle(const flutter::EncodableMap& arguments);
  void DisconnectBle();
  bool ReadBle(const flutter::EncodableMap& arguments);
  bool WriteBle(const flutter::EncodableMap& arguments);
  bool NotifyBle(const flutter::EncodableMap& arguments);
  void StartBleServer(const flutter::EncodableMap& arguments);
  void StopBleServer();
  int NotifyBleServer(const flutter::EncodableMap& arguments);
  void StartClassicScan();
  void StopClassicScan();
  void ConnectClassic(const flutter::EncodableMap& arguments);
  void StartClassicServer(const flutter::EncodableMap& arguments);
  void SendClassic(const flutter::EncodableMap& arguments);
  void StopClassic();
  void AttachClassicSocket(
      winrt::Windows::Networking::Sockets::StreamSocket socket,
      const std::string& peer);
  void ReadClassicLoop();
  void Enqueue(flutter::EncodableMap value);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  AdvertisementWatcher watcher_{nullptr};
  winrt::event_token received_token_{};
  winrt::Windows::Devices::Bluetooth::BluetoothLEDevice device_{nullptr};
  std::map<
      std::string,
      winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
          GattCharacteristic>
      characteristics_;
  std::vector<std::pair<
      winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
          GattCharacteristic,
      winrt::event_token>>
      notification_tokens_;
  winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
      GattServiceProvider gatt_provider_{nullptr};
  winrt::Windows::Devices::Bluetooth::GenericAttributeProfile::
      GattLocalCharacteristic gatt_local_characteristic_{nullptr};
  winrt::event_token gatt_read_token_{};
  winrt::event_token gatt_write_token_{};
  std::vector<uint8_t> gatt_server_value_;
  winrt::Windows::Devices::Enumeration::DeviceWatcher classic_watcher_{nullptr};
  winrt::event_token classic_added_token_{};
  winrt::event_token classic_stopped_token_{};
  winrt::Windows::Devices::Bluetooth::BluetoothDevice classic_device_{nullptr};
  winrt::Windows::Devices::Bluetooth::Rfcomm::RfcommDeviceService
      rfcomm_service_{nullptr};
  winrt::Windows::Devices::Bluetooth::Rfcomm::RfcommServiceProvider
      rfcomm_provider_{nullptr};
  winrt::Windows::Networking::Sockets::StreamSocket classic_socket_{nullptr};
  winrt::Windows::Networking::Sockets::StreamSocketListener
      classic_listener_{nullptr};
  winrt::event_token classic_connection_token_{};
  winrt::Windows::Storage::Streams::DataReader classic_reader_{nullptr};
  winrt::Windows::Storage::Streams::DataWriter classic_writer_{nullptr};
  std::thread classic_reader_thread_;
  std::atomic<bool> classic_reading_{false};
  std::mutex mutex_;
  std::queue<flutter::EncodableMap> events_;
};

#endif  // RUNNER_WINDOWS_BLUETOOTH_BRIDGE_H_
