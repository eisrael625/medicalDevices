#include <driver/dac.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <math.h>

const int refPin = 27;
const int adcPin = 34;
const char *deviceName = "MedicalDevices";
static const char *serviceUUID = "FFE0";
static const char *dataCharacteristicUUID = "FFE1";
static const char *controlCharacteristicUUID = "FFE2";

constexpr uint8_t samplesPerCycle = 8;
constexpr uint32_t carrierFreqHz = 10000;
constexpr uint32_t carrierSampleRateHz = carrierFreqHz * samplesPerCycle;
constexpr uint8_t dacMid = 128;
constexpr uint8_t dacAmp = 56;

constexpr float adcMaxCounts = 4095.0f;
constexpr float adcReferenceMv = 3300.0f;
// Empirical correction factor from scope comparison.
// Example: scope 305 mV / app 928 mV ~= 0.3287
constexpr float p2pCalibrationScale = .121f;
constexpr int captureSampleCount = 400;
constexpr int captureDelayUs = 200;
constexpr int historySize = 5;
constexpr int debugPrintStride = 40;

BLEServer *bleServer = nullptr;
BLECharacteristic *dataCharacteristic = nullptr;
BLECharacteristic *controlCharacteristic = nullptr;
bool bleClientConnected = false;
hw_timer_t *signalTimer = nullptr;
portMUX_TYPE signalTimerMux = portMUX_INITIALIZER_UNLOCKED;
volatile uint8_t carrierIndex = 0;
uint8_t sineTable[samplesPerCycle];

float p2pHistory[historySize] = {0};
uint32_t captureCount = 0;
int historyCount = 0;

class MyServerCallbacks : public BLEServerCallbacks
{
  void onConnect(BLEServer *server) override
  {
    bleClientConnected = true;
  }

  void onDisconnect(BLEServer *server) override
  {
    bleClientConnected = false;
    BLEDevice::startAdvertising();
  }
};

void resetHistory()
{
  for (int i = 0; i < historySize; ++i)
  {
    p2pHistory[i] = 0.0f;
  }
  captureCount = 0;
  historyCount = 0;
}

void pushCapture(float p2pMv)
{
  for (int i = historySize - 1; i > 0; --i)
  {
    p2pHistory[i] = p2pHistory[i - 1];
  }
  p2pHistory[0] = p2pMv;
  if (historyCount < historySize)
  {
    historyCount++;
  }
  captureCount++;
}

String buildPayload()
{
  float latest = historyCount > 0 ? p2pHistory[0] : 0.0f;
  float delta = historyCount > 1 ? (p2pHistory[0] - p2pHistory[1]) : 0.0f;

  String payload = String(captureCount) + "," +
                   String(latest, 2) + "," +
                   String(delta, 2) + "," +
                   String(historyCount);

  for (int i = 0; i < historySize; ++i)
  {
    payload += "," + String(p2pHistory[i], 2);
  }

  return payload;
}

void publishPayload()
{
  if (dataCharacteristic == nullptr)
  {
    return;
  }

  String payload = buildPayload();
  dataCharacteristic->setValue(payload.c_str());
  Serial.println(payload);

  if (bleClientConnected)
  {
    dataCharacteristic->notify();
  }
}

float captureP2PMv()
{
  float rawMin = adcMaxCounts;
  float rawMax = 0.0f;

  Serial.println("---- Capture start ----");

  for (int i = 0; i < captureSampleCount; ++i)
  {
    int raw = analogRead(adcPin);
    if (raw < rawMin)
      rawMin = raw;
    if (raw > rawMax)
      rawMax = raw;

    if (i < 10 || (i % debugPrintStride) == 0 || i == captureSampleCount - 1)
    {
      Serial.print("sample[");
      Serial.print(i);
      Serial.print("] = ");
      Serial.println(raw);
    }

    delayMicroseconds(captureDelayUs);
  }

  float p2pCounts = rawMax - rawMin;
  float uncalibratedMv = (p2pCounts / adcMaxCounts) * adcReferenceMv;
  float calibratedMv = uncalibratedMv * p2pCalibrationScale;

  Serial.print("rawMin = ");
  Serial.println(rawMin);
  Serial.print("rawMax = ");
  Serial.println(rawMax);
  Serial.print("p2pCounts = ");
  Serial.println(p2pCounts);
  Serial.print("uncalibratedMv = ");
  Serial.println(uncalibratedMv, 2);
  Serial.print("calibratedMv = ");
  Serial.println(calibratedMv, 2);
  Serial.println("---- Capture end ----");

  return calibratedMv;
}

class ControlCallbacks : public BLECharacteristicCallbacks
{
  void onWrite(BLECharacteristic *characteristic) override
  {
    String value = characteristic->getValue();

    if (value == "capture")
    {
      float p2pMv = captureP2PMv();
      pushCapture(p2pMv);
      publishPayload();
      Serial.println("Capture complete");
    }
    else if (value == "sync")
    {
      publishPayload();
    }
    else if (value == "clear")
    {
      resetHistory();
      publishPayload();
      Serial.println("History cleared");
    }
  }
};

void buildSineTable()
{
  for (int i = 0; i < samplesPerCycle; ++i)
  {
    const float phase = 2.0f * PI * ((float)i / samplesPerCycle);
    int value = dacMid + (int)(dacAmp * sinf(phase));
    if (value < 0)
      value = 0;
    if (value > 255)
      value = 255;
    sineTable[i] = (uint8_t)value;
  }
}

bool setupCarrierOutput()
{
  if (dac_output_enable(DAC_CHANNEL_1) != ESP_OK)
  {
    return false;
  }

  return dac_output_voltage(DAC_CHANNEL_1, sineTable[0]) == ESP_OK;
}

void IRAM_ATTR onSignalTimer()
{
  portENTER_CRITICAL_ISR(&signalTimerMux);

  const uint8_t index = carrierIndex;
  gpio_set_level((gpio_num_t)refPin, index < (samplesPerCycle / 2) ? 1 : 0);
  dac_output_voltage(DAC_CHANNEL_1, sineTable[index]);

  carrierIndex = index + 1;
  if (carrierIndex >= samplesPerCycle)
  {
    carrierIndex = 0;
  }

  portEXIT_CRITICAL_ISR(&signalTimerMux);
}

bool setupReferenceOutput()
{
  pinMode(refPin, OUTPUT);
  digitalWrite(refPin, LOW);

  signalTimer = timerBegin(carrierSampleRateHz);
  if (signalTimer == nullptr)
  {
    return false;
  }

  timerAttachInterrupt(signalTimer, &onSignalTimer);
  timerAlarm(signalTimer, 1, true, 0);
  return true;
}

void setupBle()
{
  BLEDevice::init(deviceName);

  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new MyServerCallbacks());

  BLEService *service = bleServer->createService(serviceUUID);

  dataCharacteristic = service->createCharacteristic(
      dataCharacteristicUUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  dataCharacteristic->addDescriptor(new BLE2902());

  controlCharacteristic = service->createCharacteristic(
      controlCharacteristicUUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE);
  controlCharacteristic->setCallbacks(new ControlCallbacks());
  controlCharacteristic->setValue("capture");

  resetHistory();
  dataCharacteristic->setValue(buildPayload().c_str());

  service->start();

  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(serviceUUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
}

void setup()
{
  Serial.begin(115200);

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  buildSineTable();
  setupBle();

  if (!setupCarrierOutput())
  {
    Serial.println("Failed to start DAC output on GPIO25");
    while (true)
    {
      delay(1000);
    }
  }

  if (!setupReferenceOutput())
  {
    Serial.println("Failed to start 10 kHz reference on GPIO27");
    while (true)
    {
      delay(1000);
    }
  }

  Serial.println("ESP32 P2P capture mode");
  Serial.println("Control writes: capture | sync | clear");
  Serial.println("Data payload: capture_count,latest_p2p_mv,delta_from_prev_mv,history_count,h1,h2,h3,h4,h5");
  Serial.println("P2P calibration scale: 0.3287");
}

void loop()
{
  delay(20);
}
