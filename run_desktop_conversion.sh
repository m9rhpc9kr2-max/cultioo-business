#!/bin/bash

# Desktop Optimization Conversion Script
# Automatically converts all Flutter pages to use desktop-optimized widgets

echo "🖥️  Desktop Optimization Converter"
echo "=================================="
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is not installed. Please install Python 3 first."
    exit 1
fi

echo "📁 Project directory: $SCRIPT_DIR"
echo ""

# Run the Python conversion script
python3 "$SCRIPT_DIR/convert_to_desktop.py" "$SCRIPT_DIR"

# Check if conversion was successful
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Conversion script completed successfully!"
    echo ""
    echo "📋 Next steps:"
    echo "  1. Review the converted files"
    echo "  2. Manually fix Scaffold and AppBar replacements"
    echo "  3. Run: flutter analyze"
    echo "  4. Run: flutter test"
    echo "  5. Test on Desktop platforms (macOS, Windows, Linux)"
    echo "  6. Test on Mobile platforms (iOS, Android)"
    echo "  7. Commit changes: git add -A && git commit -m 'Auto-convert pages to desktop-optimized'"
    echo ""
else
    echo ""
    echo "❌ Conversion script failed!"
    exit 1
fi
