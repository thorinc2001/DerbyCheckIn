# Derby Check-In

Mac apps for checking in pinewood derby racers and feeding the roster to
[GrandPrix Race Manager](https://grandprix-software-central.com) (GPRM).

- **Derby Check-In**: a native Mac app for one check-in table.
- **Derby Web Check In**: runs on one Mac and shares the same check-in screens with any
  PC, Mac, tablet or phone on the local network, through a web browser.

Both record each racer's name, race group (GPRM Rank and Subgroup), car number and name,
weight, an inspection checklist, racer and car photos, and check-in time. They import a
GPRM roster and export one GPRM can import: `GPRM Roster.csv` plus photos named by car number.

## Using it

1. Open the app and choose **Import Roster…** to load last year's or this year's GPRM roster,
   or add racers with **New Racer**.
2. At check-in: pick the racer, weigh and inspect the car, take photos, and click **Check In**.
3. Choose **Export Checked-In Racers for GPRM…**, copy the folder to the GPRM PC, copy
   `Images` into GPRM's Images folder, and import `GPRM Roster.csv` into GPRM.

Race groups and their car-number series are in **Settings › Race Groups**. The event can be
saved to OneDrive, Google Drive or any folder in **Settings › Storage**.

For Derby Web Check In, put every computer on the same network (a small travel Wi-Fi router
works anywhere, no internet needed) and open the address the app shows, or scan its QR code.

## Building

Needs macOS 14 or later and Xcode (Swift 6).

```bash
./build.sh            # builds both apps into build/
Tools/check-all.sh    # unit tests and the web API test
```

The apps are signed for this Mac only, not by Apple: on another Mac, right-click the app and
choose **Open** the first time.

See [ARCHITECTURE.md](ARCHITECTURE.md) for how the code fits together.
