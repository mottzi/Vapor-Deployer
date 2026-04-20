import glob, re
for fpath in glob.glob('Sources/Deployer/Setup/Steps/*.swift'):
    with open(fpath, 'r') as f:
        c = f.read()
    if 'let context: SetupContext' not in c:
        c = re.sub(r'(struct\s+\w+Step\s*:\s*SetupStep\s*\{)', r'\1\n\n    let context: SetupContext\n    let console: any Console', c)
    c = c.replace('func run(context: SetupContext, console: any Console) async throws', 'func run() async throws')
    with open(fpath, 'w') as f:
        f.write(c)
