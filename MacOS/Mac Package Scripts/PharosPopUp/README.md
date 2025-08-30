# MobilePrint Installer for UMD Libraries

**Purpose:**  
This installer provides the Pharos Popup print client and sets up all supported MobilePrint queues at UMD libraries.

---

##  What's Included
- `Popup.pkg` – Pharos Popup client installer.
- `install_mobileprint.command` – Script to launch Popup (if needed) and install all MobilePrint queues.
- `README.md` – This guide.

---

##  System Requirements
- macOS 11 (Big Sur) through macOS 14 (Sonoma)
- Administrative privileges (to install printers and software)

---

##  Installation Instructions

1. **Download** the `MobilePrintInstaller.dmg` file from the UMD IT portal.
2. **Double-click** the `.dmg` to mount it.
3. **Run** `install_mobileprint.command` (double-click).
   - You may be prompted to allow execution. If so:
     - Go to **System Settings → Privacy & Security**
     - Click **Allow** for the installer.
4. **Authenticate** using your Mac’s administrator password when prompted.
5. The installer will:
   - Install Popup if needed
   - Configure each MobilePrint queue listed in the script
6. Once complete, you'll see a confirmation dialog— you're ready to print!
7. **Eject** the `.dmg`.

---

##  Installed Printer Queues

Your Mac will be configured with the following print queues:

- LIB‑ArchMobileBW  
- LIB‑ArchMobileColor  
- LIB‑ArtMobileBW  
- LIB‑ArtMobileColor  
- LIB‑EPSLMobileBW  
- LIB‑EPSLMobileColor  
- LIB‑HBKMobileBW  
- LIB‑HBKMobileColor  
- LIB‑MarylandRoomMobileBW  
- LIB‑MarylandRoomMobileColor  
- LIB‑Mck2FMobileWideFormat  
- LIB‑McKMobileBW  
- LIB‑McKMobileColor  
- LIB‑PALMobileBW  
- LIB‑PALMobileColor  

---

##  Troubleshooting Tips

- If the script fails to launch, right-click and select **Open**, then approve it in **Privacy & Security**.
- For errors like “Permission denied,” ensure you're entering the correct admin password.
- If a queue doesn’t appear:
  - Check `Printers & Scanners` in System Settings.
  - Confirm your Mac is connected to the internet and can reach `LIBRPS406DV.AD.UMD.EDU` on ports 515 and 28203.
- For further assistance, contact **Library IT Support** at **[IT Helpdesk, University of Maryland]**.

---

##  Support Information

If you need help or encounter issues:

1. Include a screenshot or copy of any error messages.
2. Send your macOS version (found in **About This Mac**).
3. Email **mobileprint-support@umd.edu** with the above details and your location.

---

##  Version History

- **v1.0 (2025‑08‑30):** Initial release of the Multi‑Queue `.dmg` installer.

---

##  License & Credits

Distribution via UMD IT Services — for campus use only.  
Written and maintained by UMD Library Technology Team.

---

**Thank you for using UMD Library MobilePrint!**