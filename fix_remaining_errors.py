#!/usr/bin/env python3
"""
Fix remaining const expression errors and syntax issues
"""

import os
import re
from pathlib import Path

def fix_remaining_errors(project_root):
    """Fix all remaining errors"""
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
                    
                    # Fix 1: Remove const from lines with method invocations
                    # Pattern: const ... DesktopOptimizedWidgets.
                    content = re.sub(
                        r'const\s+([A-Z]\w*)\s*\(\s*([^)]*DesktopOptimizedWidgets\.|[^)]*DesktopAppWrapper\.)',
                        r'\1(\2',
                        content
                    )
                    
                    # Fix 2: Remove const Text with method calls
                    content = re.sub(
                        r"const\s+Text\s*\(\s*'([^']*)',\s*style:\s*TextStyle\s*\(\s*fontSize:\s*DesktopOptimizedWidgets\.",
                        r"Text('\1', style: TextStyle(fontSize: DesktopOptimizedWidgets.",
                        content
                    )
                    
                    # Fix 3: Remove const Text with double quotes
                    content = re.sub(
                        r'const\s+Text\s*\(\s*"([^"]*)"\s*,\s*style:\s*TextStyle\s*\(\s*fontSize:\s*DesktopOptimizedWidgets\.',
                        r'Text("\1", style: TextStyle(fontSize: DesktopOptimizedWidgets.',
                        content
                    )
                    
                    # Fix 4: Fix double commas
                    content = re.sub(r',\s*,', ',', content)
                    
                    # Fix 5: Fix trailing commas before closing parens
                    content = re.sub(r',\s*\)', ')', content)
                    
                    # Fix 6: Fix lines with const and method calls in general
                    lines = content.split('\n')
                    fixed_lines = []
                    for line in lines:
                        # If line has const and a method call, remove const
                        if 'const ' in line and ('DesktopOptimizedWidgets.' in line or 'DesktopAppWrapper.' in line):
                            line = line.replace('const ', '')
                        fixed_lines.append(line)
                    content = '\n'.join(fixed_lines)
                    
                    # Fix 7: Remove any remaining const before TextStyle with method calls
                    content = re.sub(
                        r'const\s+TextStyle\s*\(',
                        'TextStyle(',
                        content
                    )
                    
                    # Fix 8: Remove any remaining const before Text with method calls
                    content = re.sub(
                        r'const\s+Text\s*\(',
                        'Text(',
                        content
                    )
                    
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
    
    print("🔧 Fixing remaining const expression errors...")
    print(f"📁 Project: {project_root}")
    print()
    
    fixed = fix_remaining_errors(project_root)
    
    print()
    print(f"✅ Fixed {len(fixed)} files")
    if fixed:
        print("\n📝 Fixed files:")
        for f in sorted(set(fixed)):
            print(f"  ✅ {f}")
    
    print("\n✨ Done! Run: flutter analyze")
