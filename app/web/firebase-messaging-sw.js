// Shows push notifications in the browser when the app is closed or in the
// background, and opens the job or chat when one is tapped.
// The Firebase SDK in the page registers this file to get a push token; the
// messages themselves come from the push-send function (API.md section 8).

self.addEventListener('push', (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_) {
    payload = {};
  }
  const notification = payload.notification || {};
  const data = payload.data || {};
  const url = data.url || (payload.fcmOptions && payload.fcmOptions.link) || self.registration.scope;
  event.waitUntil(
    self.registration.showNotification(notification.title || 'Bravura Electrical', {
      body: notification.body || '',
      icon: notification.icon || 'icons/Icon-192.png',
      badge: 'icons/Icon-192.png',
      tag: data.link || undefined,
      data: { url },
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || self.registration.scope;
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
      for (const w of windows) {
        if (new URL(w.url).origin === new URL(url).origin && 'focus' in w) {
          return w.navigate(url).then((c) => (c || w).focus());
        }
      }
      return self.clients.openWindow(url);
    }),
  );
});
