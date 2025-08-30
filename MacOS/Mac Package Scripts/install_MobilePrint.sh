#!/bin/bash
set -e
echo "== Pharos Popup & MobilePrint Queues Installer =="

# 1. Install Popup client (if needed)
if [ ! -d "/Library/Application Support/Pharos" ]; then
  echo "- Installing Popup client..."
  sudo installer -pkg "$(dirname "$0")/Popup.pkg" -target /
else
  echo "- Popup client already installed."
fi

# 2. Define your printer queues
declare -A printers=(
  ["LIB-ArchMobileBW"]="popup://LIBRPS406DV.AD.UMD.EDU:515/LIB-ArchMobileBW"
  ["LIB-ArchMobileColor"]="popup://LIBRPS406DV.AD.UMD.EDU:515/LIB-ArchMobileColor"
  ["LIB-ArtMobileBW"]="popup://LIBRPS406DV.AD.UMD.EDU:515/LIB-ArtMobileBW"
  ["LIB-ArtMobileColor"]="popup://LIBRPS406DV.AD.UMD.EDU:515/LIB-ArtMobileColor"
  ["LIB-EPSLMobileBW"]="popup://LIBRPS406DV.AD.UMD.EDU:515/LIB-EPSLMobileBW"
  ["LIB-EPSLMobileColor"]="popup://LIBRPS406DV.AD.UMD.EDU:515/LIB-EPSLMobileColor"
  ["LIB-HBKMobileBW"]="popup://LIBRPS406DV.AD.UMD.EDU:515/LIB-HBKMobileBW"
  ["LIB-HBKMobileColor"]="popup://LIBRPS406DV.AD.UMD.EDU:515/LIB-HBKMobileColor"
  ["LIB-MarylandRoomMobileBW"]="popup://LIBRPS406DV.AD.UMD.EDU:515/LIB-MarylandRoomMobileBW"
  ["LIB-MarylandRoomMobileColor"]="popup://LIBRPS406DV.AD.UMD.EDU:515/LIB-MarylandRoomMobileColor"
  ["LIB-Mck2FMobileWideFormat"]="popup://LIBRPS406DV.AD.UMD.EDU:515/LIB-Mck2FMobileWideFormat"
  ["LIB-McKMobileBW"]="popup://LIBRPS406DV.AD.UMD.EDU:515/LIB-McKMobileBW"
  ["LIB-McKMobileColor"]="popup://LIBRPS406DV.AD.UMD.EDU:515/LIB-McKMobileColor"
  ["LIB-PALMobileBW"]="popup://LIBRPS406DV.AD.UMD.EDU:515/LIB-PALMobileBW"
  ["LIB-PALMobileColor"]="popup://LIBRPS406DV.AD.UMD.EDU:515/LIB-PALMobileColor"

)

PPD_PATH="/Library/Printers/PPDs/Contents/Resources/Generic.ppd"

# 3. Loop through and install each queue
for NAME in "${!printers[@]}"; do
  URI="${printers[$NAME]}"
  echo "- Configuring printer queue: ${NAME} → ${URI}"

  if lpstat -p "${NAME}" &>/dev/null; then
    echo "  • Queue '${NAME}' already exists; skipping."
  else
    sudo /usr/sbin/lpadmin \
      -p "${NAME}" \
      -E \
      -v "${URI}" \
      -P "${PPD_PATH}" \
      -o printer-is-shared=false
    echo "  • Queue '${NAME}' created."
  fi
done

echo "All queues installed. You're ready to print!"