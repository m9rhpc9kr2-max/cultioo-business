#!/usr/bin/env python3
"""
Fix syntax errors from conversion script
"""

import os
from pathlib import Path

# Files with known syntax errors
files_to_fix = [
    "lib/auth/pages/login_page.dart",
    "lib/auth/pages/register_page.dart",
    "lib/modules/business/pages/business_account_page.dart",
    "lib/modules/business/pages/products_page.dart",
    "lib/modules/delvioo/pages/delvioo_account_page.dart",
]

for file_path_str in files_to_fix:
    file_path = Path(file_path_str)
    if not file_path.exists():
        print(f"❌ File not found: {file_path}")
        continue
    
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    modified = False
    
    # Fix specific known issues
    for i, line in enumerate(lines):
        # Fix: style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 6)),
        # Should be: style: TextStyle(fontSize: DesktopOptimizedWidgets.getFontSize() + 6)),
        # The issue is extra closing parens
        
        # Pattern: )),  -> ),
        if line.count('))') > line.count('(('):
            # Count opening and closing parens
            opens = line.count('(')
            closes = line.count(')')
            if closes > opens:
                # Remove extra closing parens
                while closes > opens:
                    line = line.rstrip()
                    if line.endswith('))'):
                        line = line[:-1]
                        closes -= 1
                    elif line.endswith(')'):
                        line = line[:-1]
                        closes -= 1
                    else:
                        break
                lines[i] = line + '\n'
                modified = True
    
    if modified:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.writelines(lines)
        print(f"✅ Fixed: {file_path}")
    else:
        print(f"⏭️  No changes needed: {file_path}")

print("\n✨ Done!")
