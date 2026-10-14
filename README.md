# Deploy Agent

`deploy_agent.sh` is a bash script that sets up the Student Attendance Tracker for me, runs it, and archives its logs. It also handles Ctrl+C and Ctrl+Z safely while a deployment is happening.

I did not change `attendance_checker.py`. Everything here is shell scripting around it.

## Video walkthrough

Video link: https://www.loom.com/share/e15b2bbe722d42b0833f7f6f415a76fa

The video explains my approach, how the script was built, and the logic behind each section. It also shows a live marking session, the edge cases, and an interrupt (Ctrl+C) in the middle of a deployment.

## Project layout

```
deploy_agent_GithubUsername/
├── deploy_agent.sh
├── README.md
└── templates/
    ├── attendance_checker.py
    ├── assets.csv
    └── config.json
```

## How to run the script

1. Open a terminal in the folder that contains `deploy_agent.sh` and `templates/`.
2. Make the script executable (only needed once):
   ```
   chmod +x deploy_agent.sh
   ```
3. Start it:
   ```
   ./deploy_agent.sh
   ```

The script must be started from this folder, because it looks for `templates/` there.

## How to select a feature

I used an interactive menu. After starting the script you see:

```
===== Deploy Agent =====
1) Deploy the application
2) Run the application
3) Archive the log files
4) Quit
```

Type the number and press Enter. The menu comes back after each feature until you choose 4. Anything other than 1 to 4 gives a message and shows the menu again.

## Feature 1: Deploy the application

What happens, in order:

1. **Pre-flight checks.** It checks that `python3` and `zip` are installed and prints the python3 version. If one is missing, it prints an error and stops.
2. **Project name.** It asks for a name and creates `attendance_tracker_<name>/`. An empty name is rejected. If the folder already exists, it asks whether to overwrite. Answering anything except `y` aborts and changes nothing.
3. **Folders and files.** It creates `Helpers/` and `reports/`, then copies `attendance_checker.py` and `config.json` from `templates/` without changing them. If creating folders or copying fails, it prints an error and cleans up.
4. **Roster.** I choose A or B:
   - **A:** copies the number of students I ask for (1 to 10) from `templates/assets.csv`, plus the header row. These students have 4 prior sessions, so `total_sessions` stays at 5.
   - **B:** generates the number of students I ask for (1 to 10) with Attendance Count and Absence Count both at 0. This is the first session, so the script changes `total_sessions` to 1 in the deployed `config.json` only. The template file is not touched.
5. **Permissions.** `chmod +x` makes `attendance_checker.py` executable. `chmod 600` makes `Helpers/config.json` readable and writable by the owner only. The script prints both files with `ls -l` as confirmation.
6. **Thresholds.** See the next section.
7. **Verify.** It runs the app (Feature 2). If the app starts, the structure, roster and config work together.

### Why total_sessions must match the roster

`total_sessions` is the number of sessions including today's. It must always be one more than the prior sessions recorded in the roster. Option A rows have 4 prior sessions, so the total is 5. Option B rows have 0, so the total is 1.

## How the threshold update works

After the permissions step, the script asks `Do you want to update the alert thresholds? (y/n)`.

- If I type anything except `y`, the defaults in `config.json` stay (warning 75, failure 50).
- If I type `y`, it asks for a **warning** value (default 75) and a **failure** value (default 50). Pressing Enter keeps the default.
- Each value is checked before it is used. It must be a whole number from 0 to 100. If I type something like `abc`, `7a` or `150`, it prints a message and asks again.
- Then `sed -i` edits only the `"warning"` and `"failure"` lines of the deployed `config.json`. The rest of the file keeps its order and formatting.

## Feature 2: Run the application

It checks the tools, asks for the project name, then goes into `attendance_tracker_<name>/` and runs `python3 attendance_checker.py`. The app is interactive, so I mark each student present or absent. If the project does not exist, the script says to deploy it first.

## Feature 3: Archive the log files

After a marking session, the app creates `reports/attendance.log` and `reports/absent.log`. Feature 3 archives them:

1. It asks for the project name and checks the folder exists.
2. It creates a timestamp with `date +%Y%m%d_%H%M%S`, for example `20261014_184600`.
3. It creates `archives/attendance/` and `archives/absent/` if they do not exist yet.
4. Each log that exists is **copied** into its own folder with the timestamp in the name:

```
attendance_tracker_<name>/
└── archives/
    ├── attendance/
    │   └── attendance_20261014_184600.log
    └── absent/
        └── absent_20261014_184600.log
```

5. It prints the final path of each archived file.
6. If a log is missing (for example nobody was absent, so there is no `absent.log`), it prints a message and skips it. It does not crash.

Because the logs are copied, the originals stay in `reports/`. The timestamp makes every archived name unique.

## Ctrl+C and Ctrl+Z handling (the archive trigger)

While a deployment is in progress, the script uses `trap` to catch **Ctrl+C (SIGINT)** and **Ctrl+Z (SIGTSTP)**. The trap turns on once the project name is accepted and any overwrite is done. It turns off again when deployment finishes, just before the app starts. It is not active while the marking session runs.

When either key is pressed, the script:

1. Prints that the deployment was interrupted.
2. Zips whatever exists of `attendance_tracker_<name>/` into `attendance_tracker_<name>_archive.zip` using the `zip` command.
3. Deletes the incomplete project folder, so no half-made directory is left behind.
4. Prints that it is closing, and exits.

If the key is pressed before any folder exists, it says nothing was created and exits without making a zip.

### What the .zip contains

Only what had been built at the moment of the interrupt. For example:

- Interrupted at the roster question: `Helpers/` (with `config.json`), `reports/` and `attendance_checker.py`. There is no `assets.csv` yet.
- Interrupted later: also `assets.csv`, and the edited `config.json` if the thresholds were already changed.

### How to test it

1. Run `./deploy_agent.sh` and choose `1`.
2. Enter a name, for example `test`.
3. At the `Choose A or B:` question, press Ctrl+C. Repeat in another run with Ctrl+Z.
4. Check the results:
   ```
   ls
   unzip -l attendance_tracker_test_archive.zip
   ```
   The `.zip` should be listed, `attendance_tracker_test/` should be gone, and the zip listing shows the partial project.

## How I tested the deployed structure

After a deploy, I ran:

```
ls -R attendance_tracker_<name>
```

and compared it with the required layout: `attendance_checker.py` in the project root, `Helpers/assets.csv`, `Helpers/config.json`, and an empty `reports/`. I also checked:

- `ls -l` shows `attendance_checker.py` is executable and `config.json` is `-rw-------` (600).
- `config.json` has the correct `total_sessions` (5 for Option A, 1 for Option B) and the thresholds I typed.
- The app starts at the end of Feature 1 and writes the logs into `reports/` after marking.
- Edge cases: an existing folder name (overwrite prompt), invalid threshold input, a missing `absent.log`, and Ctrl+C and Ctrl+Z during deploy.

## Notes

- `sed -i` works on Linux and WSL. It behaves differently on macOS.
- Project names should not contain spaces.
