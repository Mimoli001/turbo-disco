# Free Virtual Machine by Github Action

[繁體中文](supports/README-zh.md) [English](#)

:warning: Reminder: If you are facing errors when starting the systems and vps, please fork and pull the newest version of codes of this repo to your forked repo. Press [here](#Updating-Codes) for steps. 
Totally FREE for everyone to enjoy your own MacOS, Windows 10 and ubuntu vps.

## Screenshots:
<details>
    <summary>Windows 10</summary>
<br>
    
- Windows 10 Version
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/268600af-c8b9-47cf-b5dd-d1c1ed6d9ce9.png">

- Windows 10 Task Manager
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/0cf98258-a6fe-46bb-ac9a-ee4bb3037e3a.png" >

- Windows 10 Device Manager
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/d32cf285-5ecf-4cce-a52a-5cb54fb130c7.png">

- Windows 10 Device Specification
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/e1852b80-d550-44f3-b619-86ea82902bb4.png">
    
</details>

<details>
    <summary>Ubuntu (SSH Version)</summary>
<br>

1. Click **Run Workflox**
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/96644176-D760-47D4-BED2-C47E62A6763F.png" >

2. Copy ssh with url
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/0F804C5F-FE8F-45FA-9720-F91F212597DF.png" >

3. Open cmd or Terminal from your windows/MacOS or Linux, and type command provided by github actions boxes.
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/78FE6C5A-7270-4986-AB8F-57EC4C9B4F44.png" >

type **yes** from the connect, and then type your ssh password by secrets of LINUX_USER_PASSWORD u have set.

4. Type **sudo -i** for root permission and type your password.
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/E5527744-1ED1-4550-8867-EF4EC76D6895.png" >

5. Enjoy having your FREE linux SSH VPS and type any command you want.(but only 6 hours)
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/E6E9EA63-AC24-4FDB-AAF9-8B509658440A.png" >

</details>

<details>
    <summary>Ubuntu (Desktop Remote Version)</summary>
<br>

- Desktop Screenshot
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/4EB9C2FF-9D03-4998-A440-D7716A0F7CD0.png" >

- Linux Chrome
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/09F0A4CF-9B30-44CD-8DC4-139D03DFC2CC.png" >

- Install any apps you want :)
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/A0886141-DF1E-4379-88E7-F00EDAD87D0E.png">

</details>

<details>
    <summary>MacOS</summary>
<br>

- Desktop Screenshot
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/Screenshot%202021-02-23%20at%207.32.41%20AM.png" >

- Settings
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/Screenshot%202021-02-23%20at%207.32.21%20AM.png" >

- RAM
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/Screenshot%202021-02-23%20at%207.32.58%20AM.png" >

- Storage
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/Screenshot%202021-02-23%20at%207.33.18%20AM.png" >

- Pre-Installed Apps
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/Screenshot%202021-02-23%20at%207.34.10%20AM.png" >

</details>

## Machine Specification:
Specs below are the standard GitHub-hosted runners used by this project in **public** repositories (free and unlimited there):

### Windows and Linux:
- 4-core vCPU
- 16 GB RAM
- 14 GB SSD Disk **(Excluded System used)**

### macOS (`macos-latest`, Apple silicon)
- 3-core vCPU (Apple M1)
- 7 GB RAM
- 14 GB SSD Disk **(Excluded System used)**

> :warning: These specs apply to **public** forks. If you fork this repository as **private**, Linux/Windows runners are smaller (2-core vCPU / 8 GB RAM), consume the 2,000 free Actions minutes per month (Windows counts 2x, macOS 10x per minute), and macOS concurrency is limited to 5 jobs.

> :information_source: The Windows workflow runs on GitHub's Windows Server runner with Remote Desktop enabled (the desktop looks similar to Windows 10/11).

## Setting up:
1. Fork this project
2. Go to your peoject page, click `Settings` and go to `Secrets`, and then click `New Secret` to add these secrets below:

Secrets Name | Uses | Notes
----- | ----- | -----
`MAC_REALNAME` | For MacOS User Display Name | Type any name you want
`MAC_USER_PASSWORD` | For MacOS System Admin Password | Type any password you want
`NGROK_AUTH_TOKEN` | For **ngrok** tunnel uses | Go to website, and copy the API key from https://dashboard.ngrok.com/get-started/your-authtoken :warning: On the ngrok **free** plan, TCP tunnels (SSH/RDP/VNC) require a verified credit card on your ngrok account.
`VNC_PASSWORD` | For the login password of VNC remote authentication | Type any password you want
`WINDOWS_USER_PASSWORD` | For Windows RDP login password | Type any password you want; the workflow sets it as the RDP account password
`LINUX_USERNAME` | For linux system username | Type any name you want
`LINUX_USER_PASSWORD` | For linux shell and root password | Type any password you want
`LINUX_MACHINE_NAME` | For Linux System Computer name | Type any name you want
`CHROME_HEADLESS_CODE` | For remoting linux desktop using google remote | Copy Codes from [here](https://remotedesktop.google.com/headless) and login with your google account, and then copy the code below `Debian Linux` blank. :warning: Each code can only be used for once, generate another code when u have used that one.
`GOOGLE_REMOTE_PIN` | PIN used by Google Remote Desktop | Type any PIN of at least 6 digits, you will need it when connecting to the Linux desktop

## Deloy and Run
<details>
    <summary>MacOS Install and Run</summary>
<br>
    
1. go to `Actions` Tab and select one of system workflow.

2. Click `Run Workflow` button on the left of `This workflow has a workflow_dispatch event trigger` line.

3. Wait until a few minutes.

4. Go to https://dashboard.ngrok.com/status/tunnels and check if theres a one online tunnel running.

5. Copy the link(**without tcp://**) and go to VNC Viewer(Download and install it), input the link to connect area u copied from the website.

6. Fill in those login info, within username `koolisw`and password from `VNC_PASSWORD` you typed.

7. Enjoy!

</details>

<details>
    <summary>Windows 10</summary>
<br>

1. First, start the Windows workflow from the `Actions` tab.
2. Second, wait for the `Print connection info` step in the job log - it prints your `mstsc /v:HOST:PORT` address, username and password. You can also check https://dashboard.ngrok.com/status/tunnels
3. Open Windows Remote Desktop Connection (`mstsc`) or Microsoft Remote Desktop and connect using that address.
4. ENJOY!

</details>

<details>
    <summary>Linux</summary>
<br>

1. First, start the actions of Linux System.
2. Second, Copy the link from the console
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/0F804C5F-FE8F-45FA-9720-F91F212597DF.png" >
3. Go to MacOS Terminal or Windows CMD Terminal or else ssh client and enter command provided. Enter your ssh password then.
<img src="https://raw.githubusercontent.com/RealKoolisw/image/main/VirtualMachine-GHAction/sceenshots/78FE6C5A-7270-4986-AB8F-57EC4C9B4F44.png" >
4. ENJOY!

</details>


- Reminders:
:warning: Dont stop the workflow while you are connected. The machine (and your remote session) lives only until the **6 hours** GitHub Actions limit, then everything is deleted.

:warning: Dont install system updates (macOS, Windows or big system updates on any machine) on your virtual machine while connected, they may reboot it and break your remote process.

## Updating Codes
<details>
    <summary>Click Here to Expand</summary>
<br>

To pull the newest version of this project into your own fork:

**Option A (on GitHub):** open your fork, click the **Sync fork** button next to the branch name and press **Update branch**.

**Option B (from a terminal):**

```bash
git remote add upstream https://github.com/cybershadowvps/FreeVPS.git   # only the first time
git fetch upstream
git merge upstream/main      # or: git rebase upstream/main
git push
```

Your fork now runs the newest workflows and scripts.

</details>

## Limits: 
1. Each virtual machine can only run up to **6** hours of execution time (this is the hard job execution limit of GitHub-hosted runners). If the virtual machine reaches this limit, the job is terminated and everything is cleared.
2. Not suggested for you saving some of important and sensitive files to each machine, be risked that all files will be deleted and cannot be undo.
3. Since we are using **ngrok**, the free plan allows up to **3** online tunnels (endpoints) at the same time, so you may run up to three of these systems concurrently. :warning: On the free plan **TCP tunnels (SSH / RDP / VNC) require credit card verification** on your ngrok account, and are limited to 100 TCP connections/minute, 5,000 TCP connections/month and 1 GB data transfer/month (see https://ngrok.com/pricing).
4. Not suggested to login any account from any website (just like **Google or Microsoft**), since **VNC** connection is not encrypted and easily been accessed other people.
5. Actions on **public** repositories are free and unlimited. On a **private** fork the 2,000 free minutes per month are shared by all workflows (Linux counts 1x, Windows 2x and macOS 10x per minute).
6. On the GitHub Free plan at most **20** jobs run at the same time (**5** of them can be macOS jobs).

## Suggestions and Best Tricks:
- If you are facing slow and laggy remote control experience from **MacOS** or **Windows**, you can use either **Google Remote Desktop** or **Microsoft Remote Control** for a faster and smoother remotes.
- We highly recommanded you **fork** this project to change username and other displaying names for systems.
