const { contextBridge } = require("electron");

contextBridge.executeInMainWorld({
  func: () => {
    if (window.top !== window) return;

    const platform = Object.getOwnPropertyDescriptor(Navigator.prototype, "platform").get;
    let mac = false;
    Object.defineProperty(navigator, "platform", {
      configurable: true,
      get() {
        return mac ? "MacIntel" : platform.call(this);
      },
    });

    const kanataOptionEdits = new Set(["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Backspace", "Delete"]);
    const override = (event, values) => {
      for (const [name, value] of Object.entries(values)) Object.defineProperty(event, name, { value });
    };
    const end = () => {
      mac = false;
    };
    const inputsWithEnd = new WeakSet();

    const start = (event) => {
      const input = event.target;
      if (!(input instanceof HTMLTextAreaElement) || !input.classList.contains("t3-ghostty-input")) return;

      const { ctrlKey, metaKey, shiftKey, key } = event;
      if (ctrlKey && !metaKey && shiftKey && key === "Backspace") {
        override(event, { ctrlKey: false, shiftKey: false, metaKey: true });
      } else if (ctrlKey && !metaKey && kanataOptionEdits.has(key)) {
        override(event, { ctrlKey: false, altKey: true });
      } else {
        override(event, { ctrlKey: metaKey, metaKey: ctrlKey });
      }
      mac = true;

      if (!inputsWithEnd.has(input)) {
        inputsWithEnd.add(input);
        for (const type of ["keydown", "keyup"]) {
          input.addEventListener(type, (e) => {
            if (e.cancelBubble) end();
          });
        }
      }
      setTimeout(end);
    };

    for (const type of ["keydown", "keyup"]) {
      window.addEventListener(type, start, true);
      window.addEventListener(type, end);
    }
  },
});
