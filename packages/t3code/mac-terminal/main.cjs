const path = require("node:path");
const { app } = require("electron");

app.on("session-created", (session) => {
  session.registerPreloadScript({
    type: "frame",
    filePath: path.join(__dirname, "terminal-keys.cjs"),
  });
});

require(path.join(app.getAppPath(), "@appMain@"));
