# Temperature simulator, sending telemetry data to the Azure IoT Hub.
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
import os
import hmac
import hashlib
import base64
from azure.iot.device import Message
from azure.iot.device.aio import IoTHubDeviceClient
from azure.iot.device.aio import ProvisioningDeviceClient
from azure.iot.device.exceptions import ConnectionFailedError


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

    def generate_device_key(self, primmary_key, device_id) -> str:
        signature = hmac.new(
            base64.b64decode(primmary_key),
            msg=device_id.encode('ascii'),
            digestmod=hashlib.sha256
        )
        hash = base64.b64encode(signature.digest()).decode('ascii')
        return hash

def stdin_listener():
    """
    Listener for quitting the program
    """
    while True:
        selection = input("Press Q to quit\n")
        if selection == "Q" or selection == "q":
            print("Quitting...")
            break

async def provision_device(config: Config):

    provisioning_device_client = ProvisioningDeviceClient.create_from_symmetric_key(
        provisioning_host=config.provisioning_host,
        registration_id=config.device_id,
        id_scope=config.id_scope,
        symmetric_key=config.device_key,
    )
    return await provisioning_device_client.register()


async def main():

    try:
        config = Config()
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

    # Connect the IoT device client
    await device_client.connect()

    # Run the stdin listener in the event loop
    loop = asyncio.get_running_loop()
    user_finished = loop.run_in_executor(None, stdin_listener)
   
    # Wait for user to quit the program from the terminal
    await user_finished

    # Shut down the client
    await device_client.shutdown()


if __name__ == '__main__':
    asyncio.run(main())
