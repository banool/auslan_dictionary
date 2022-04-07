import argparse
import asyncio
import logging
import re


# The list of iOS simulators to run.
# This comes from inspecting `xcrun simctl list`
IOS_SIMULATORS = [
    "iPhone 8",
    "iPhone 8 Plus",
    "iPhone 13 Pro Max",
    "iPad Pro (12.9-inch) (5th generation)",
    "iPad Pro (9.7-inch)",
]

ANDROID_EMULATORS = [
    "Nexus_7_API_32",
    "Nexus_10_API_32",
    "Pixel_5_API_32",
]


LOG = logging.getLogger(__name__)
formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
ch = logging.StreamHandler()
ch.setFormatter(formatter)
LOG.addHandler(ch)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("-d", "--debug", action="store_true")
    parser.add_argument("--clear-screenshots", action="store_true", help="Delete all existing screenshots")
    args = parser.parse_args()
    return args


async def run_command(command):
    proc = await asyncio.create_subprocess_exec(
        *command,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await proc.communicate()
    if stderr:
        LOG.debug(f"stderr of command {command}: {stderr}")
    return stdout.decode("utf-8")


async def get_uuids_of_ios_simulators(simulators):
    command_output = await run_command(["xcrun", "simctl", "list"])

    out = {}
    for s in simulators:
        for line in command_output.splitlines():
            r = "    " + re.escape(s) + r" \((.*)\) \(.*"
            m = re.match(r, line)
            if m is not None:
                out[s] = m[1]

    return out


async def start_ios_simulators(uuids_of_ios_simulators):
    async def start_ios_simulator(uuid):
        await run_command(["xcrun", "simctl", "boot", uuid])

    await asyncio.gather(
        *[start_ios_simulator(uuid) for uuid in uuids_of_ios_simulators.values()]
    )


async def start_android_emulators(android_emulator_names):
    async def start_android_emulator(name):
        await run_command(["flutter", "emulators", "--launch", name])

    await asyncio.gather(
        *[start_android_emulator(name) for name in android_emulator_names]
    )


async def get_all_device_ids():
    raw = await run_command(["flutter", "devices"])
    out = []
    for line in raw.splitlines():
        if "•" not in line:
            continue
        if "Daniel" in line:
            continue
        if "Chrome" in line:
            continue
        device_id = line.split("•")[1].lstrip().rstrip()
        out.append(device_id)

    return out


async def run_tests(device_ids):
    async def run_test(device_id):
        LOG.info(f"Started testing for {device_id}")
        await run_command(
            [
                "flutter",
                "drive",
                "--driver=test_driver/integration_driver.dart",
                "--target=integration_test/screenshot_test.dart",
                "-d",
                device_id,
            ]
        )
        LOG.info(f"Finished testing for {device_id}")

    for device_id in device_ids:
        await run_test(device_id)

    # await asyncio.gather(*[run_test(device_id) for device_id in device_ids])


async def main():
    args = parse_args()

    if args.debug:
        LOG.setLevel("DEBUG")
    else:
        LOG.setLevel("INFO")

    if args.clear_screenshots:
        await run_command(["rm", "ios/*"])
        await run_command(["rm", "android/*"])
        LOG.info("Cleared existing screenshots")

    uuids_of_ios_simulators = await get_uuids_of_ios_simulators(IOS_SIMULATORS)
    LOG.info(f"iOS simulatior name to UUID: {uuids_of_ios_simulators}")

    LOG.info("Launching iOS simulators")
    await start_ios_simulators(uuids_of_ios_simulators)
    LOG.info("Launched iOS simulators")

    LOG.info("Launching Android emulators")
    await start_android_emulators(ANDROID_EMULATORS)
    LOG.info("Launched Android emulators")

    await asyncio.sleep(5)

    device_ids = await get_all_device_ids()
    LOG.debug(f"Device IDs: {device_ids}")

    LOG.info("Running tests")
    await run_tests(device_ids)
    LOG.info("Ran tests")

    LOG.info("Uploading to Apple")
    await upload_to_apple()
    LOG.info("Uploaded to Apple")

    LOG.info("Uploading to Google")
    await upload_to_google()
    LOG.info("Uploaded to Google")

    LOG.info("Done!")


if __name__ == "__main__":
    asyncio.run(main())
