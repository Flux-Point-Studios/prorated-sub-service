#!/usr/bin/env python3
import json
import sys

def parse_path(path):
    """Parse a jq-style path like .fields[2].int"""
    parts = path.strip('.').split('.')
    result = []
    for part in parts:
        if '[' in part:
            key, idx = part.split('[')
            idx = int(idx.rstrip(']'))
            if key:
                result.append(key)
            result.append(idx)
        else:
            result.append(part)
    return result

def get_value(data, path):
    """Get value from nested dict/list using path"""
    if not path or path == '.':
        return data
    
    parts = parse_path(path)
    current = data
    
    for part in parts:
        if isinstance(part, int):
            current = current[part]
        else:
            current = current.get(part, None)
        if current is None:
            return None
    
    return current

if __name__ == "__main__":
    # Read from stdin or file
    if len(sys.argv) > 1 and sys.argv[1] != '-r':
        # Simple path query
        data = json.load(sys.stdin)
        path = sys.argv[1] if len(sys.argv) > 1 else '.'
        result = get_value(data, path)
        
        if isinstance(result, (dict, list)):
            print(json.dumps(result, indent=2))
        elif result is None:
            print("null")
        else:
            print(result)
    else:
        # Just pretty print
        data = json.load(sys.stdin)
        print(json.dumps(data, indent=2)) 