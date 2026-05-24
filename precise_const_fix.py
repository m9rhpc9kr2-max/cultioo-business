#!/usr/bin/env python3
"""
Precise const fix - only remove const before specific patterns
"""

import os
import re
from pathlib import Path

lib_path = Path(".") / "lib"
fixed = 0

for root, dirs, files in os.walk(lib_path):
    for file in files:
        if file.endswith(".dart"):
            file_path = Path(root) / file
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            original = content
            
            # Only remove const when followed by widget name and ( and contains Desktop method
            # Use negative lookahead to ensure we don't break anything
            patterns = [
                (r'const\s+(TextStyle\s*\([^)]*DesktopOptimizedWidgets\.)', r'\1'),
                (r'const\s+(TextStyle\s*\([^)]*DesktopAppWrapper\.)', r'\1'),
                (r'const\s+(Text\s*\([^)]*DesktopOptimizedWidgets\.)', r'\1'),
                (r'const\s+(Text\s*\([^)]*DesktopAppWrapper\.)', r'\1'),
                (r'const\s+(SizedBox\s*\([^)]*DesktopOptimizedWidgets\.)', r'\1'),
                (r'const\s+(SizedBox\s*\([^)]*DesktopAppWrapper\.)', r'\1'),
            ]
            
            for pattern, replacement in patterns:
                content = re.sub(pattern, replacement, content, flags=re.DOTALL)
            
            if content != original:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(content)
                fixed += 1
                print(f"✅ {file_path.relative_to('.')}")

print(f"\n✅ Fixed {fixed} files")
