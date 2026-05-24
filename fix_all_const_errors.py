#!/usr/bin/env python3
"""
Fix ALL const expression errors - comprehensive fix
"""

import os
import re
from pathlib import Path

def fix_all_const_errors(project_root):
    """Fix all const expression errors in the project"""
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
                    
                    # Fix 1: Remove const from SizedBox with method calls
                    content = re.sub(
                        r'const\s+SizedBox\(',
                        'SizedBox(',
                        content
                    )
                    
                    # Fix 2: Remove const from TextStyle with method calls
                    content = re.sub(
                        r'const\s+TextStyle\(',
                        'TextStyle(',
                        content
                    )
                    
                    # Fix 3: Remove const from BoxDecoration with method calls
                    content = re.sub(
                        r'const\s+BoxDecoration\(',
                        'BoxDecoration(',
                        content
                    )
                    
                    # Fix 4: Remove const from Text with method calls
                    content = re.sub(
                        r'const\s+Text\(',
                        'Text(',
                        content
                    )
                    
                    # Fix 5: Remove const from Container with method calls
                    content = re.sub(
                        r'const\s+Container\(',
                        'Container(',
                        content
                    )
                    
                    # Fix 6: Remove const from ClipRRect with method calls
                    content = re.sub(
                        r'const\s+ClipRRect\(',
                        'ClipRRect(',
                        content
                    )
                    
                    # Fix 7: Remove const from Row with method calls
                    content = re.sub(
                        r'const\s+Row\(',
                        'Row(',
                        content
                    )
                    
                    # Fix 8: Remove const from Column with method calls
                    content = re.sub(
                        r'const\s+Column\(',
                        'Column(',
                        content
                    )
                    
                    # Fix 9: Remove const from Padding with method calls
                    content = re.sub(
                        r'const\s+Padding\(',
                        'Padding(',
                        content
                    )
                    
                    # Fix 10: Remove const from Icon with method calls
                    content = re.sub(
                        r'const\s+Icon\(',
                        'Icon(',
                        content
                    )
                    
                    # Fix 11: Remove const from EdgeInsets with method calls
                    content = re.sub(
                        r'const\s+EdgeInsets\.',
                        'EdgeInsets.',
                        content
                    )
                    
                    # Fix 12: Remove const from BorderRadius with method calls
                    content = re.sub(
                        r'const\s+BorderRadius\.',
                        'BorderRadius.',
                        content
                    )
                    
                    # Fix 13: Remove double commas
                    content = re.sub(r',\s*,', ',', content)
                    
                    # Fix 14: Remove trailing commas before closing parens
                    content = re.sub(r',\s*\)', ')', content)
                    
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
    
    print("🔧 Fixing ALL const expression errors...")
    print(f"📁 Project: {project_root}")
    print()
    
    fixed = fix_all_const_errors(project_root)
    
    print()
    print(f"✅ Fixed {len(fixed)} files")
    if fixed:
        print("\n📝 Fixed files:")
        for f in sorted(set(fixed)):
            print(f"  ✅ {f}")
    
    print("\n✨ Done! Run: flutter run -d macos")
