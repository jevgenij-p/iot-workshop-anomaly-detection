#
# IoT device simulator, sending telemetry data to the Azure IoT Hub.
#
# To run the program
#   1) Activate environment (in Windows):
#       env\Scripts\activate
#   2) Set environment variables:
#       DPS_ENDPOINT (optional)
#       DPS_ID_SCOPE
#       DEVICE_ID
#       DPS_PRIMARY_KEY
#   3) Run the following command:
#       python telemetry.py
#
# See documentation:
#   Symmetric key attestation:
#       https://docs.microsoft.com/en-us/azure/iot-dps/concepts-symmetric-key-attestation?tabs=azure-cli#group-enrollments
#       https://docs.microsoft.com/en-us/azure/iot-dps/how-to-legacy-device-symm-key?tabs=windows

import asyncio
import random
import json
import os
import hmac
import hashlib
import base64
import functools
from azure.iot.device import Message
from azure.iot.device.aio import IoTHubDeviceClient
from azure.iot.device.aio import ProvisioningDeviceClient
from azure.iot.device.exceptions import ConnectionFailedError


BASE_TEMPERATURE = 20.0
BASE_HUMIDITY = 60.0
TEMPERATURE_INCREMENT = 2
DELAY = 2.0

class Config:
    def __init__(self):
        self.provisioning_host = (
            os.getenv("DPS_ENDPOINT")
            if os.getenv("DPS_ENDPOINT")
            else "global.azure-devices-provisioning.net"
            )
        self.id_scope = os.getenv("DPS_ID_SCOPE")
        self.device_id = os.getenv("DEVICE_ID")
        self.primary_key = os.getenv("DPS_PRIMARY_KEY")
        self.device_key = self.generate_device_key(self.primary_key, self.device_id)
        self.base_temperature = BASE_TEMPERATURE

    def generate_device_key(self, primmary_key, device_id) -> str:
        signature = hmac.new(
            base64.b64decode(primmary_key),
            msg=device_id.encode('ascii'),
            digestmod=hashlib.sha256
        )
        hash = base64.b64encode(signature.digest()).decode('ascii')
        return hash

def print_help():
    print("\nPress the following key and <Enter>:")
    print("   +  to increase temperature")
    print("   -  to decrease temperature")
    print("   q  to quit\n")

def stdin_listener(config: Config):
    """
    Listener for quitting the program
    """
    while True:
        selection = input()
        key = selection.lower()
        if key == "q":
            print("\nQuitting...")
            break
        if key == "+":
            config.base_temperature += TEMPERATURE_INCREMENT
            print("Temperature increased")
        if key == "-":
            config.base_temperature -= TEMPERATURE_INCREMENT
            print("Temperature decreased")

def get_telemetry(config: Config) -> dict:

    temperature_noise = (random.random() * 2) - 1
    temperature = round(config.base_temperature + temperature_noise, 2)
    humidity_noise = (random.random() * 3) - 1
    humidity = round(BASE_HUMIDITY + humidity_noise, 2)
    telemetry = { "temperature": temperature, "humidity": humidity }
    print(f"Message: temperature: {temperature}  humidity: {humidity}")
    return telemetry

async def provision_device(config: Config):

    provisioning_device_client = ProvisioningDeviceClient.create_from_symmetric_key(
        provisioning_host=config.provisioning_host,
        registration_id=config.device_id,
        id_scope=config.id_scope,
        symmetric_key=config.device_key,
    )
    return await provisioning_device_client.register()

async def send_telemetry(device_client, config):
    print("Sending telemetry...")

    while True:
        try:
            telemetry = get_telemetry(config)
            message = Message(json.dumps(telemetry), content_encoding = "utf-8", content_type = "application/json")
        except RuntimeError as error:
            print(error.args[0])
            await asyncio.sleep(1)
            continue

        await device_client.send_message(message)
        await asyncio.sleep(DELAY)


async def main():

    print("IoT Device Simulator")
    config = Config()
    try:
        registration_result = await provision_device(config)
        
        if registration_result.status == "assigned":
            print("IoT Device was assigned")
            print(f"Assigned Hub: {registration_result.registration_state.assigned_hub}")
            print(f"Device id: {registration_result.registration_state.device_id}")

            device_client = IoTHubDeviceClient.create_from_symmetric_key(
                symmetric_key=config.device_key,
                hostname=registration_result.registration_state.assigned_hub,
                device_id=registration_result.registration_state.device_id)
        else:
            raise RuntimeError("Could not provision device. Aborting Plug and Play device connection.")
    except ConnectionFailedError as error:
        print(error.args[0])
        exit()

    print_help()

    # Connect the IoT device client
    await device_client.connect()

    # Schedule the send_telemetry() task
    send_telemetry_task = asyncio.create_task(send_telemetry(device_client, config))

    # Run the stdin listener in the event loop
    loop = asyncio.get_running_loop()
    user_finished = loop.run_in_executor(None, functools.partial(stdin_listener, config))

    # Wait for user to quit the program from the terminal
    await user_finished

    send_telemetry_task.cancel()

    # Shut down the client
    await device_client.shutdown()


if __name__ == '__main__':
    asyncio.run(main())
