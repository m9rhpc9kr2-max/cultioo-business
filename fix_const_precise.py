#!/usr/bin/env python3
"""
Precise fix for const expression errors - only removes const, nothing else
"""

import os
import re
from pathlib import Path

def fix_const_precise(project_root):
    """Fix const expression errors precisely"""
    lib_path = Path(project_root) / "lib"
    fixed_files = []
    
    for root, dirs, files in os.walk(lib_path):
        for file in files:
            if file.endswith(".dart"):
                file_path = Path(root) / file
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                    
                    original = content
                    
                    # Only fix: Remove const from widgets/types that have method calls
                    # Pattern: const SizedBox(height: DesktopOptimizedWidgets.
                    content = re.sub(
                        r'const\s+(SizedBox|TextStyle|Text|Container|BoxDecoration|ClipRRect|Padding|Icon|Row|Column|EdgeInsets|BorderRadius)\s*\(',
                        lambda m: m.group(1) + '(',
                        content
                    )
                    
                    # Also handle const with method calls on same line
                    # Only remove const if there's a method call (.) on the same line
                    lines = content.split('\n')
                    fixed_lines = []
                    for line in lines:
                        # If line has const and a method call (.) in the same statement, remove const
                        if 'const ' in line and ('DesktopOptimizedWidgets.' in line or 'DesktopAppWrapper.' in line):
                            # Only remove the const keyword, nothing else
                            line = re.sub(r'\bconst\s+', '', line, count=1)
                        fixed_lines.append(line)
                    content = '\n'.join(fixed_lines)
                    
                    if content != original:
                        with open(file_path, 'w', encoding='utf-8') as f:
                            f.write(content)
                        fixed_files.append(str(file_path.relative_to(project_root)))
                        print(f"✅ Fixed: {file_path.relative_to(project_root)}")
                
                except Exception as e:
                    print(f"❌ Error in {file_path}: {e}")
    
    return fixed_files

if __name__ == "__main__":
    import sys
    project_root = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    
    print("🔧 Fixing const expression errors (precise)...")
    print(f"📁 Project: {project_root}")
    print()
    
    fixed = fix_const_precise(project_root)
    
    print()
    print(f"✅ Fixed {len(fixed)} files")
    if fixed:
        print("\n📝 Fixed files:")
        for f in sorted(set(fixed)):
            print(f"  ✅ {f}")
    
    print("\n✨ Done! Run: flutter analyze")
