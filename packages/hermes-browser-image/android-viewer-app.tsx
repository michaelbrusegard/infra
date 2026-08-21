import React, { useEffect, useRef, useState } from "react";
import { Emulator } from "../lib";

type ViewerSize = {
  width: number;
  height: number;
};

const DEVICE_WIDTH = 1080;
const DEVICE_HEIGHT = 2400;
const CONTROLS_WIDTH = 180;

function fitViewer(): ViewerSize {
  const availableWidth = Math.max(1, window.innerWidth - CONTROLS_WIDTH);
  const availableHeight = Math.max(1, window.innerHeight);
  const scale = Math.min(
    availableWidth / DEVICE_WIDTH,
    availableHeight / DEVICE_HEIGHT,
  );
  return {
    width: Math.max(1, Math.floor(DEVICE_WIDTH * scale)),
    height: Math.max(1, Math.floor(DEVICE_HEIGHT * scale)),
  };
}

function sendFallbackInput(payload: Record<string, unknown>) {
  void fetch("http://127.0.0.1:8080/api/v1/emulator/input", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

function FallbackFramebuffer({ width, height }: ViewerSize) {
  const [frame, setFrame] = useState(Date.now());
  const mouseDown = useRef(false);

  const refresh = (delay: number) => {
    window.setTimeout(() => setFrame(Date.now()), delay);
  };
  const pointer = (event: React.MouseEvent<HTMLDivElement>, buttons: number) => {
    const rect = event.currentTarget.getBoundingClientRect();
    const x = Math.round(((event.clientX - rect.left) / rect.width) * DEVICE_WIDTH);
    const y = Math.round(((event.clientY - rect.top) / rect.height) * DEVICE_HEIGHT);
    sendFallbackInput({ type: "mouse", x, y, buttons });
  };

  return (
    <div
      className="fallback"
      style={{ width, height }}
      tabIndex={0}
      onMouseDown={(event) => {
        mouseDown.current = true;
        event.currentTarget.focus();
        pointer(event, event.button === 2 ? 2 : 1);
      }}
      onMouseMove={(event) => {
        if (mouseDown.current) pointer(event, 1);
      }}
      onMouseUp={(event) => {
        mouseDown.current = false;
        pointer(event, 0);
      }}
      onMouseLeave={(event) => {
        if (mouseDown.current) pointer(event, 0);
        mouseDown.current = false;
      }}
      onContextMenu={(event) => event.preventDefault()}
      onKeyDown={(event) => {
        event.preventDefault();
        sendFallbackInput({ type: "keyboard", event: "keydown", key: event.key });
      }}
      onKeyUp={(event) => {
        event.preventDefault();
        sendFallbackInput({ type: "keyboard", event: "keyup", key: event.key });
      }}
    >
      <img
        src={`http://127.0.0.1:8080/api/v1/emulator/screenshot?frame=${frame}`}
        draggable={false}
        onLoad={() => refresh(250)}
        onError={() => refresh(1000)}
      />
      <span>Framebuffer fallback</span>
    </div>
  );
}

function App() {
  const emulatorRef = useRef<any>(null);
  const [viewerSize, setViewerSize] = useState<ViewerSize>(fitViewer);
  const [state, setState] = useState("connecting");
  const [error, setError] = useState("");
  const [generation, setGeneration] = useState(0);

  useEffect(() => {
    const resize = () => setViewerSize(fitViewer());
    window.addEventListener("resize", resize);
    return () => window.removeEventListener("resize", resize);
  }, []);

  const sendKey = (key: string) => {
    if (state === "connected") {
      emulatorRef.current?.sendKey(key);
    } else {
      sendFallbackInput({ type: "keyboard", event: "keypress", key });
    }
  };
  const reconnect = () => {
    setError("");
    setState("connecting");
    setGeneration((value) => value + 1);
  };

  return (
    <main>
      <section className="screen" aria-label="Android emulator screen">
        <div className={`webrtc ${state === "connected" ? "visible" : ""}`}>
          <Emulator
            key={generation}
            ref={emulatorRef}
            uri="127.0.0.1:8080"
            width={viewerSize.width}
            height={viewerSize.height}
            muted={true}
            onStateChange={(nextState: string) => {
              setState(nextState);
              if (nextState === "connected") setError("");
            }}
            onError={(cause: unknown) => {
              setState("disconnected");
              setError(cause instanceof Error ? cause.message : String(cause));
            }}
          />
        </div>
        {state === "connected" ? null : <FallbackFramebuffer {...viewerSize} />}
      </section>
      <aside>
        <div>
          <h1>Hermes Android</h1>
          <p className={`status ${state}`}>{state}</p>
          <p className="backend">Emulator framebuffer</p>
          {error ? <p className="error">{error}</p> : null}
        </div>
        <nav aria-label="Android hardware controls">
          <button onClick={() => sendKey("GoBack")}>Back</button>
          <button onClick={() => sendKey("GoHome")}>Home</button>
          <button onClick={() => sendKey("AppSwitch")}>Recents</button>
          <button onClick={() => sendKey("AudioVolumeUp")}>Volume +</button>
          <button onClick={() => sendKey("AudioVolumeDown")}>Volume −</button>
          <button onClick={() => sendKey("Power")}>Power</button>
        </nav>
        <button className="reconnect" onClick={reconnect}>Reconnect</button>
      </aside>
    </main>
  );
}

const style = document.createElement("style");
style.textContent = `
  :root { color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, sans-serif; }
  * { box-sizing: border-box; }
  html, body, #root { width: 100%; height: 100%; margin: 0; overflow: hidden; background: #080b10; }
  body { user-select: none; }
  main { width: 100%; height: 100%; display: flex; align-items: center; justify-content: space-between; }
  .screen { position: relative; flex: 1; height: 100%; display: flex; align-items: center; justify-content: center; background: #000; }
  .webrtc { visibility: hidden; }
  .webrtc.visible { visibility: visible; }
  .fallback { position: absolute; overflow: hidden; outline: none; background: #000; cursor: default; }
  .fallback img { display: block; width: 100%; height: 100%; object-fit: contain; pointer-events: none; }
  .fallback span { position: absolute; right: 8px; bottom: 8px; padding: 4px 7px; border-radius: 5px; background: rgba(0,0,0,.64); color: #b9c9dd; font-size: 10px; }
  aside { width: ${CONTROLS_WIDTH}px; height: 100%; padding: 22px 14px; display: flex; flex-direction: column; justify-content: space-between; gap: 24px; border-left: 1px solid #273142; background: #101722; }
  h1 { margin: 0 0 12px; font-size: 19px; line-height: 1.15; }
  p { margin: 0; }
  .status { display: inline-block; padding: 5px 9px; border-radius: 999px; background: #293446; color: #dce5f2; font-size: 12px; text-transform: capitalize; }
  .status.connected { background: #123d2b; color: #8ff0bb; }
  .status.disconnected { background: #4b2025; color: #ffb5bc; }
  .backend { margin-top: 10px; color: #8e9bae; font-size: 11px; }
  .error { margin-top: 12px; max-height: 240px; overflow: hidden; color: #ffb5bc; font-size: 10px; line-height: 1.35; word-break: break-word; }
  nav { display: grid; gap: 10px; }
  button { width: 100%; min-height: 48px; border: 1px solid #344258; border-radius: 10px; background: #1a2534; color: #f4f7fb; font: inherit; font-weight: 650; cursor: pointer; }
  button:hover, button:focus-visible { border-color: #7198d0; background: #26384f; outline: none; }
  button:active { transform: translateY(1px); }
  .reconnect { min-height: 40px; color: #b9c9dd; font-size: 12px; }
`;
document.head.appendChild(style);

export default App;
