# UMD Library Printers - Important Setup Information

## ✅ Installation Complete!

Your UMD library printers have been successfully installed. However, you may need to configure your Mac's firewall to allow printing.

---

## ⚠️ SECURITY WARNING ON FIRST INSTALL

macOS may show: "cannot be opened because it is from an unidentified developer"

## Installation Options

### Getting Security Warnings?
Use **Install_with_Bypass.command** for a hassle-free installation

### Standard Installation  
Double-click the .pkg file (may require security approval in System Settings)

### To Install:
1. **Right-click** the installer package
2. Select **Open** from the menu
3. Click **Open** in the warning dialog
4. Enter your password and continue

OR

1. After seeing the error, go to System Settings > Privacy & Security
2. Find the message about the blocked package
3. Click **Open Anyway**

---

## FIREWALL CONFIGURATION REQUIRED

If you have macOS Firewall enabled, you MUST allow the Pharos Popup app to accept incoming connections for printing to work properly.

### When You'll See This:
The first time you try to print, macOS may show a dialog asking:
> "Do you want the application 'Pharos Popup.app' to accept incoming network connections?"

**Always click "Allow"**

### If You Clicked "Deny" By Mistake (or printing isn't working):

1. Open **System Settings** (or System Preferences on older macOS)
2. Go to **Network** > **Firewall** (or Security & Privacy > Firewall)
3. Click **Firewall Options...** 
4. Look for **"Pharos Popup"** in the list:
   - If it shows ❌ "Block incoming connections" - click it and change to ✅ **"Allow incoming connections"**
   - If it's not in the list, click the **+** button
   - Navigate to: `/Library/Application Support/Pharos/`
   - Select **Pharos Popup.app** and click **Add**
   - Make sure it's set to **Allow incoming connections**
5. Click **OK** to save

### Alternative Method (Terminal):
If you're comfortable with Terminal, you can run:
```
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "/Library/Application Support/Pharos/Popup.app"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "/Library/Application Support/Pharos/Popup.app"
```

---

## 🖨️ HOW TO PRINT

1. Open any document and press **⌘P** (Cmd+P)
2. Select a UMD printer from the dropdown:
   - Names start with **"LIB-"**
   - **BW** = Black & White printing (cheaper)
   - **Color** = Color printing
   - **WideFormat** = Large format printing (McKeldin only)
3. Click **Print**
4. Enter your **Directory ID** and password when prompted
5. Go to any library print release station
6. Log in with your campus ID card or credentials
7. Select your job and release it

---

## PRINTER LOCATIONS

- **McKeldin Library**: Firstr and Second Floor
- **Architecture Library**: First floor
- **Art Library**: Near entrance
- **EPSL (Engineering)**: First floor
- **Hornbake Library**: First floor
- **PAL (Performing Arts)**: Main floor by Service Desk
- **Maryland Room**: First Floor

---

## TROUBLESHOOTING

### Printing Not Working?
1. **Check firewall settings** (see above)
2. **Verify network connection** - Must be on campus network or VPN
3. **Check print balance** - Ensure you have credits at print station
4. **Restart print system**:
   ```
   sudo launchctl stop org.cups.cupsd
   sudo launchctl start org.cups.cupsd
   ```

### "Damaged App" Error?
This has been automatically handled during installation. If you see this error, contact IT support.

### Can't See Printers?
1. Log out and back into macOS
2. Or restart your Mac
3. Check that printers are installed:
   - System Settings > Printers & Scanners
   - Should see printers starting with "LIB-"

---

## NEED HELP?

**UMD IT Service Desk**
- Email: lib-helpdesk@umd.edu  
- Web: https://lib.umd.edu
- Walk-in: McKeldin Library, First Floor

---

## INSTALLED PRINTERS

You now have access to all UMD library printers:

**Black & White Printers:**
- LIB-McKMobileBW (McKeldin)
- LIB-ArchMobileBW (Architecture)
- LIB-ArtMobileBW (Art)
- LIB-EPSLMobileBW (Engineering)
- LIB-HBKMobileBW (Hornbake)
- LIB-PALMobileBW (Performing Arts)
- LIB-MarylandRoomMobileBW (Maryland Room)

**Color Printers:**
- LIB-McKMobileColor (McKeldin)
- LIB-ArchMobileColor (Architecture)
- LIB-ArtMobileColor (Art)
- LIB-EPSLMobileColor (Engineering)
- LIB-HBKMobileColor (Hornbake)
- LIB-PALMobileColor (Performing Arts)
- LIB-MarylandRoomMobileColor (Maryland Room)

**Special Format:**
- LIB-Mck2FMobileWideFormat (McKeldin - Large format printing)

---

*Package Version: 2.5.0*