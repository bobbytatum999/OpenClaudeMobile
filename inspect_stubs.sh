#!/bin/bash
PROJECT_DIR="/tmp/OpenClaudeMobile/Sources"
echo "=== Analyzing Files for Potential Stubs ==="
find "$PROJECT_DIR" -name "*.swift" | while read file; do
    echo "File: $file"
    # Look for empty methods or methods that just return a default value
    grep -nE "func .*\(.*\) .* \{.*return (true|false|nil|0|\"\")?.*\}" "$file"
    # Look for empty closures
    grep -n " = { [^;]* }" "$file"
done
