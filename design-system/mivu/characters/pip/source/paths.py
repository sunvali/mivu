"""Read the explicit M/L/C/Z path subset used by Pip's editable vector master."""
import re

def commands(path):
    values = re.findall(r'[MLCZ]|-?\d+(?:\.\d+)?', path)
    index = 0
    while index < len(values):
        command = values[index]
        count = {'M': 2, 'L': 2, 'C': 6, 'Z': 0}[command]
        yield command, tuple(float(v) for v in values[index+1:index+1+count])
        index += count + 1
