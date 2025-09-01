#!/bin/bash
# Script to remove all UMD printers for testing purposes

echo "==========================================="
echo "UMD Printer Removal Script"
echo "==========================================="
echo ""

# Check for admin privileges
if ! sudo -n true 2>/dev/null; then
    echo "🔐 Administrator privileges required..."
    sudo -v || exit 1
fi

echo "🔍 Finding installed UMD printers..."
echo ""

# Get list of all UMD printers
PRINTERS=$(lpstat -p 2>/dev/null | grep "LIB-" | awk '{print $2}')

if [ -z "$PRINTERS" ]; then
    echo "✅ No UMD printers found on system"
    exit 0
fi

# Count and display printers
COUNT=$(echo "$PRINTERS" | wc -l | tr -d ' ')
echo "Found $COUNT UMD printer(s):"
echo "$PRINTERS" | while read printer; do
    echo "  • $printer"
done

echo ""
echo "🗑️  Removing printers..."

# Remove each printer
echo "$PRINTERS" | while read printer; do
    if [ ! -z "$printer" ]; then
        echo "   Removing: $printer"
        sudo lpadmin -x "$printer" 2>/dev/null
    fi
done

echo ""
echo "🔍 Verifying removal..."
REMAINING=$(lpstat -p 2>/dev/null | grep -c "LIB-" || echo "0")

if [ "$REMAINING" -eq "0" ]; then
    echo "✅ All UMD printers successfully removed"
else
    echo "⚠️  Warning: $REMAINING printer(s) may still be installed"
fi

echo ""
echo "==========================================="
echo "Cleanup complete!"
echo "==========================================="
echo ""
echo "You can now run a fresh installation test."