#include <math.h>

const int dacPin = 25;
const int refPin = 27;
const int adcPin = 34;

const int numSamples = 64;
const int signalHz = 1000;
const int amplitude = 70;
const int offset = 128;

uint8_t sineTable[numSamples];
int sampleIndex = 0;

unsigned long lastSampleMicros = 0;
unsigned long samplePeriodUs = 0;

float adcRunningAvg = 0.0;
int adcCount = 0;

void buildSineTable() {
  for (int i = 0; i < numSamples; i++) {
    float theta = 2.0f * PI * i / numSamples;
    int value = offset + (int)(amplitude * sin(theta));

    if (value < 0) value = 0;
    if (value > 255) value = 255;

    sineTable[i] = (uint8_t)value;
  }
}

void setup() {
  Serial.begin(115200);

  pinMode(refPin, OUTPUT);

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  buildSineTable();

  samplePeriodUs = 1000000UL / (signalHz * numSamples);

  Serial.println("running");
}

void loop() {
  unsigned long now = micros();

  if (now - lastSampleMicros >= samplePeriodUs) {
    lastSampleMicros += samplePeriodUs;

    // continuous DAC output
    dacWrite(dacPin, sineTable[sampleIndex]);

    // continuous sync output
    if (sampleIndex < numSamples / 2) {
      digitalWrite(refPin, HIGH);
    } else {
      digitalWrite(refPin, LOW);
    }

    // occasional ADC read, but only one read at a time
    int raw = analogRead(adcPin);
    adcRunningAvg += raw;
    adcCount++;

    // print once every 64 reads
    if (adcCount >= 64) {
      float avg = adcRunningAvg / adcCount;
      Serial.println(avg);
      adcRunningAvg = 0.0;
      adcCount = 0;
    }

    sampleIndex++;
    if (sampleIndex >= numSamples) {
      sampleIndex = 0;
    }
  }
}
