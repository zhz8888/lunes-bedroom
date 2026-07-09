const { spawn } = require("child_process");

// Binary and config definitions
const apps = [
  {
    name: "xy",
    binaryPath: "/home/container/xy/xy",
    args: ["-c", "/home/container/xy/config.json"]
  },
  {
    name: "h2",
    binaryPath: "/home/container/h2/h2",
    args: ["server", "-c", "/home/container/h2/config.yaml"]
  }
];

// Run binary with keep-alive
function runProcess(app) {
  const child = spawn(app.binaryPath, app.args, { stdio: "inherit" });

  child.on("exit", (code) => {
    console.log(`[EXIT] ${app.name} exited with code: ${code}`);
    console.log(`[RESTART] Restarting ${app.name}...`);
    setTimeout(() => runProcess(app), 3000); // restart after 3s
  });
}

// Main execution
function main() {
  try {
    for (const app of apps) {
      runProcess(app);
    }
  } catch (err) {
    console.error("[ERROR] Startup failed:", err);
    process.exit(1);
  }
}

main();
