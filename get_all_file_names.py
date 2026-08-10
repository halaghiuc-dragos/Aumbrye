import os
import sys

# Forces Python to use UTF-8 even if the Windows terminal doesn't want to
if sys.stdout.encoding != 'utf-8':
    sys.stdout = open(sys.stdout.fileno(), mode='w', encoding='utf-8', buffering=1)

IGNORE_FOLDERS = {
    'node_modules', 'venv', '.venv', 'dist', 'build', '.git', 
    'out', 'target', '.idea', '.vscode', '__pycache__'
}

def generate_tree(dir_path, prefix=""):
    try:
        entries = sorted(os.listdir(dir_path), key=lambda x: (not os.path.isdir(os.path.join(dir_path, x)), x.lower()))
    except PermissionError:
        return

    entries = [e for e in entries if e not in IGNORE_FOLDERS]
    
    for i, entry in enumerate(entries):
        path = os.path.join(dir_path, entry)
        is_last = (i == len(entries) - 1)
        
        connector = "└── " if is_last else "├── "
        print(f"{prefix}{connector}{entry}")
        
        if os.path.isdir(path):
            extension_prefix = "    " if is_last else "│   "
            generate_tree(path, prefix + extension_prefix)

if __name__ == "__main__":
    print(f"Project Structure for: {os.path.basename(os.getcwd())}/")
    generate_tree('.')
