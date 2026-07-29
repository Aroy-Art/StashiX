
```
tmp/booklib → Lib root
├── Massive Publishing → Publisher
│   └── The Disavowed (2025-) → Series Name, Start Date, No end date, still ongoing
│       ├── The Disavowed 001 (2025) (digital) (Knight Ripper-Empire).cbz → No Volume, 1 issue, Date, source format is "digital", can be "scans" etc
│       ├── The Disavowed 002 (2025) (digital) (Knight Ripper-Empire).cbz → No Volume, 2 issue, Date, source format is "digital", can be "scans" etc
│       └── The Disavowed 003 (2026) (digital) (Knight Ripper-Empire).cbz
├── New American Library → Publisher
│   └── One-Shot
│       └── Stephen King's Creepshow [Signet] (1982).cbz → Single book no series, name, date
├── Semmel Verlach → Publisher
│   └── One-Shot
│       └── Gazoline and the Red Planet (1991).cbz → Single book no series, name, date
├── TOKYOPOP  → Publisher
│   └── One-Shot → Books that are single and dont have a series
│       └── NOiSE (2007).cbz → Single book no series, name, date
└── Viz Graphic Novels → Publisher
    ├── AD Police (1994) → Series Name, Start Date, No end date
    │   ├── AD Police (1994) - Chapter 1.cbz → No Volume, first issue, Date
    │   ├── AD Police (1994) - Chapter 1.jpg → Issue cover image
    │   ├── AD Police (1994) - Chapter 2.cbz → No Volume, Sencond issue, Date
    │   ├── AD Police (1994) - Chapter 3.cbz
    │   ├── AD Police (1994) - Chapter 4.cbz
    │   ├── AD Police (1994) - Chapter 5.cbz
    │   ├── cover.jpg → Series Cover image
    │   └── index.json
    ├── Ashen Victor (1997) → Series Name, Start Date, No end date
    │   ├── Ashen Victor (1997) v01 c1.cbz → Volume 1, Issue 1, Date
    │   ├── Ashen Victor (1997) v01 c2.cbz → Volume 1, Issue 2, Date
    │   ├── Ashen Victor (1997) v01 c3.cbz
    │   ├── Ashen Victor (1997) v01 c4.cbz
    │   ├── cover-1.jpg
    │   ├── cover.jpg → Series Cover image
    │   └── index.json
    └── Battle Angel Alita (1994-1998) → Series Name, Start Date, End Date
        ├── Volume 1 - Rusty Angel.cbz → Volume 1, Issue 1, No date
        ├── Volume 1 - Rusty Angel.jpg → Issue 1 cover image 
        ├── Volume 2 - Tears of an Angel.cbz → Volume 1, Issue 2, No date
        ├── Volume 2 - Tears of an Angel.jpg → Issue 2 cover image
        ├── Volume 3 - Killing Angel.cbz
        ├── Volume 3 - Killing Angel.jpg
        ├── Volume 4 - Angel of Victory.cbz
        ├── Volume 4 - Angel of Victory.jpg
        ├── Volume 5 - Angel of Redemption.cbz
        ├── Volume 5 - Angel of Redemption.jpg
        ├── Volume 6 - Angel of Death.cbz
        ├── Volume 6 - Angel of Death.jpg
        ├── Volume 7 - Angel of Chaos.cbz
        ├── Volume 7 - Angel of Chaos.jpg
        ├── Volume 8 - Fallen Angel.cbz
        ├── Volume 8 - Fallen Angel.jpg
        ├── Volume 9 - Angel's Ascension.cbz
        └── Volume 9 - Angel's Ascension.jpg
```


Step 1: Validate if Stashix needs to scan

    On all scans, Stashix will validate that all library folders are not empty and can be accessed. If they cannot, the scan is aborted. For a series, Stashix also checks the folder path on disk for the series exists, if it does not, the scan gets aborted.

Step 2: Scan the directories

    The scanner is pretty smart, it avoids as much work as possible by default.
    For each folder (in a library or for a given series), Stashix first checks if the folder has changed since our last scan. This checks at a minute level, so seconds will be ignored. This validates on the Last Write Time of the folder. (Note: Last Write time requires scanning all nested folders to accurately report the last time that folder has changed)
    Stashix checks for libraries glob pattern and parse if it exists. This allows Glob patterns to apply to the scanner and ignore certain files or folders. This applies recursively.
    Files that are ignored in the libraries Exclude Settings will not show during the can.

Step 3: Processing files

    The library dictates the rules for the parser and there are different parsers for different file types.
    The parser parses out any information from the files, these files are a list of files collected from the folder scan in the previous step and are assumed to be one series
    After parsing, Stashix checks any series need to be merged together. Merging might happen if there are ComicInfo’s with a LocalizedSeries tag which allows 2 different names to be merged automatically. Note: If there are multiple series in one folder with a localizedSeries tag, they will group incorrectly. Stashix will log this, but not stop the scan. This is not a valid configuration.
    For each found series in the folder (should be one), Stashix invokes a process series task

Step 4: Process Series

    This is responsible for taking the processed data and updating the Database. This runs parallel with other process series tasks. This may make the logs difficult to understand.
    The first thing that needs to happen is find the series in the Database. This is done by checking against the Series name and localized name. If neither exists, a new series will be created.
    In here, Stashix does all the underlying db work and update fields, etc.
    Lastly Stashix queues tasks to perform Cover Generation and File Analysis. These again will run in parallel and are scheduled on the same queue as other scan tasks.
