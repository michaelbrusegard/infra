package com.hermes.agent.clipboard;

import android.content.ClipData;
import android.os.IBinder;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.util.Base64;

public final class Main {
  private static final String SHELL_PACKAGE = "com.android.shell";

  private Main() {}

  public static void main(String[] args) throws Exception {
    IBinder binder =
        (IBinder)
            Class.forName("android.os.ServiceManager")
                .getMethod("getService", String.class)
                .invoke(null, "clipboard");
    Object clipboard =
        Class.forName("android.content.IClipboard$Stub")
            .getMethod("asInterface", IBinder.class)
            .invoke(null, binder);
    if (args.length == 2 && args[0].equals("set")) {
      String text = new String(Base64.getDecoder().decode(args[1]), StandardCharsets.UTF_8);
      call(clipboard, "setPrimaryClip", ClipData.newPlainText(null, text));
      return;
    }
    if (args.length == 1 && args[0].equals("get")) {
      ClipData clip = (ClipData) call(clipboard, "getPrimaryClip", null);
      CharSequence text = clip == null || clip.getItemCount() == 0 ? null : clip.getItemAt(0).getText();
      byte[] bytes = (text == null ? "" : text.toString()).getBytes(StandardCharsets.UTF_8);
      System.out.println(Base64.getEncoder().encodeToString(bytes));
      return;
    }
    System.err.println("usage: get | set BASE64");
    System.exit(2);
  }

  private static Object call(Object clipboard, String name, ClipData clip) throws Exception {
    for (Method method : clipboard.getClass().getMethods()) {
      if (!method.getName().equals(name)) {
        continue;
      }
      Class<?>[] types = method.getParameterTypes();
      Object[] values = new Object[types.length];
      boolean named = false;
      for (int index = 0; index < types.length; index++) {
        if (types[index] == ClipData.class) {
          values[index] = clip;
        } else if (types[index] == String.class && !named) {
          values[index] = SHELL_PACKAGE;
          named = true;
        } else if (types[index] == int.class) {
          values[index] = 0;
        }
      }
      return method.invoke(clipboard, values);
    }
    throw new NoSuchMethodException(name);
  }
}
