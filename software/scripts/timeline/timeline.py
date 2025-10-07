import pandas as pd
import matplotlib.pyplot as plt
import re
import os
import matplotlib as mpl

# Use a TrueType font and set larger font sizes globally
mpl.rcParams['font.family'] = 'DejaVu Sans'  # or any installed TTF font you prefer
mpl.rcParams['font.size'] = 12
mpl.rcParams['axes.titlesize'] = 14
mpl.rcParams['axes.labelsize'] = 12
mpl.rcParams['xtick.labelsize'] = 10
mpl.rcParams['ytick.labelsize'] = 10
mpl.rcParams['legend.fontsize'] = 12

# Load CSV
csv_path = 'data_gemm.csv'
df = pd.read_csv(csv_path)

# Sort by PC to ensure correct program order
df = df.sort_values(by='pc').reset_index(drop=True)

# Convert to list of tuples
raw_data = list(df[['inst', 'type', 'start cycle', 'end cycle']].itertuples(index=False, name=None))

# Parse registers function
def parse_regs(instr):
    instr = instr.strip()
    if instr.startswith(('add', 'addi', 'sub', 'slli', 'ori')):
        parts = instr.split()
        rd_rs = parts[1].split(',')
        rd = rd_rs[0].strip()
        rs = [x.strip() for x in rd_rs[1:]]
        return rd, rs
    elif instr.startswith('flw'):
        parts = instr.split()
        rd = parts[1].strip().strip(',')
        rs1 = re.findall(r'\((.*?)\)', instr)
        return rd, rs1
    elif instr.startswith('vle32.v'):
        parts = instr.split()
        vd = parts[1].strip().strip(',')
        rs1 = re.findall(r'\((.*?)\)', instr)
        return vd, rs1
    elif instr.startswith('vfmacc.vf'):
        parts = instr.split()
        vd = parts[1].strip().strip(',')
        rs = [x.strip().strip(',') for x in parts[2:]]
        return vd, rs
    elif instr.startswith(('beqz', 'bgeu', 'bne')):
        parts = instr.split()
        rs = [parts[1].strip().strip(',')]
        return None, rs
    else:
        return None, []

# Build all_tasks preserving program order
all_tasks = []
for i, (instr, core, start, end) in enumerate(raw_data):
    dest, srcs = parse_regs(instr)
    instr_type = instr.split()[0]
    all_tasks.append({
        'instr': instr,
        'core': core,
        'start': start,
        'end': end,
        'dest': dest,
        'srcs': srcs,
        'instr_type': instr_type,
        'program_order': i  # preserve original order
    })

# === Allocate rows within each type while preserving program order ===
def allocate_rows(tasks):
    rows = []
    output = []
    for task in tasks:
        instr, core, start, end = task['instr'], task['core'], task['start'], task['end']
        placed = False
        for idx, row in enumerate(rows):
            if all(not (start < e and end > s) for _, s, e in row):
                row.append((instr, start, end))
                task['row'] = idx
                placed = True
                break
        if not placed:
            rows.append([(instr, start, end)])
            task['row'] = len(rows) - 1
        output.append(task)
    return output

# Split by type
scalar_tasks = [t for t in all_tasks if t['core'] == 'scalar']
fp_tasks = [t for t in all_tasks if t['core'] == 'fp']
vector_tasks = [t for t in all_tasks if t['core'] == 'vector']

# Allocate rows within each type
scalar_tasks = allocate_rows(scalar_tasks)
fp_tasks = allocate_rows(fp_tasks)
vector_tasks = allocate_rows(vector_tasks)

# Merge back to all_tasks with updated row indices
all_tasks_updated = scalar_tasks + fp_tasks + vector_tasks
# Re-sort to restore original program order for dependency analysis
all_tasks_updated.sort(key=lambda x: x['program_order'])

# === Dependency analysis ===
reg_write_map = {}
dependencies = []
for idx, task in enumerate(all_tasks_updated):
    dest, srcs, program_order, instr_type = task['dest'], task['srcs'], task['program_order'], task['instr_type']
    for src in srcs:
        if src in reg_write_map:
            producer_task = reg_write_map[src]
            # Only add selected type of instructions
            if instr_type in ['vfmacc.vf']:
                # Only add dependency if producer is earlier in program order
                if producer_task['program_order'] < program_order:
                    dependencies.append({
                        'producer': producer_task,
                        'consumer': task
                    })
    if dest:
        reg_write_map[dest] = task

# === Plotting ===
fig, ax = plt.subplots(figsize=(30, 12))

# Colors for each type
colors = {'scalar': 'skyblue', 'fp': 'lightgreen', 'vector': 'salmon'}

# Plot each task
for task in all_tasks_updated:
    instr = task['instr']
    core = task['core']
    start = task['start']
    end = task['end']
    row = task['row']
    instr_type = task['instr_type']
    program_order = task['program_order']
    y = f"{core.capitalize()} Row {row}"
    ax.barh(y, end - start, left=start, color=colors.get(core, 'gray'), edgecolor='black')
    ax.text((start + end) / 2, y, instr, ha='center', va='center', fontsize=12, rotation=45)
    # ax.text((start + end) / 2, y, f"{instr_type} ({program_order})", ha='center', va='center', fontsize=12, rotation=45)
# Plot dependencies
for dep in dependencies:
    p = dep['producer']
    c = dep['consumer']
    p_x = p['end']
    p_y = f"{p['core'].capitalize()} Row {p['row']}"
    c_x = c['start']
    c_y = f"{c['core'].capitalize()} Row {c['row']}"
    ax.annotate("", xy=(c_x, c_y), xytext=(p_x, p_y),
                arrowprops=dict(arrowstyle="->", color='gray', lw=1))

ax.set_xlabel('Cycle')
ax.set_title('Execution Timeline with Correct Program Order Dependencies')
ax.grid(axis='x')

# Set y-ticks
scalar_yticks = [f"Scalar Row {i}" for i in range(max([t['row'] for t in scalar_tasks])+1)]
fp_yticks = [f"Fp Row {i}" for i in range(max([t['row'] for t in fp_tasks])+1)]
vector_yticks = [f"Vector Row {i}" for i in range(max([t['row'] for t in vector_tasks])+1)]
yticks = scalar_yticks + fp_yticks + vector_yticks

ax.set_yticks(yticks)
ax.set_yticklabels(yticks)

plt.tight_layout()

# Create outputs directory if it doesn't exist
output_dir = 'outputs'
os.makedirs(output_dir, exist_ok=True)

# Save PNG and PDF
plt.savefig(os.path.join(output_dir, 'execution_timeline.png'), dpi=300)
plt.savefig(os.path.join(output_dir, 'execution_timeline.pdf'))
# Show the plot
plt.show()
