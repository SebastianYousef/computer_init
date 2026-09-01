This is for students who are tired of logging in to new school computers configuring the basics over and over.

Instead, just run the script(s) you want and make your life that much easier.

Just run: 
git clone https://github.com/SebastianYousef/computer_init.git

## macOS / Ubuntu

Then run 
bash {The file you wish to run}

## Windows

Double-click the `.bat` file for the script you want:

    vscode_windows.bat    -> installs VSCode + the 'code' command
    github_windows.bat    -> sets up git, gh and your GitHub SSH key

The `.bat` is just a launcher — it runs the matching `.ps1` script for you so
you don't have to change PowerShell's execution policy. If you prefer running it
yourself from a PowerShell window:

    powershell -ExecutionPolicy Bypass -File .\vscode_windows.ps1

Enjoy!
