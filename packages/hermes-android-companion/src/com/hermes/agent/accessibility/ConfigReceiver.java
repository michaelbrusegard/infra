package com.hermes.agent.accessibility;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public final class ConfigReceiver extends BroadcastReceiver {
    static final String PREFERENCES = "hermes_companion";
    static final String TOKEN_KEY = "auth_token";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!"com.hermes.agent.accessibility.CONFIGURE".equals(intent.getAction())) {
            return;
        }
        String token = intent.getStringExtra("token");
        if (token == null || token.length() < 32 || token.length() > 512) {
            return;
        }
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .edit()
                .putString(TOKEN_KEY, token)
                .apply();
    }
}
