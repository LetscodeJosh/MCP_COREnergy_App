const CACHE_NAME = 'mcp-profiling-v1';
const ASSETS = [
  './',
  './index.html',
  './style.css',
  './app.js',
  './mock_data.js',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css',
  'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js'
];

// Install Event
self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      console.log('[Service Worker] Caching app shell');
      return cache.addAll(ASSETS);
    })
  );
});

// Activate Event
self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) {
            console.log('[Service Worker] Removing old cache', key);
            return caches.delete(key);
          }
        })
      );
    })
  );
});

// Fetch Event (Network-first with offline fallback)
self.addEventListener('fetch', (e) => {
  // Only handle local/http assets, ignore browser extensions or analytics
  if (e.request.url.startsWith('http') || e.request.url.includes('leaflet')) {
    e.respondWith(
      fetch(e.request)
        .then((response) => {
          // Clone the response and cache it
          const resClone = response.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(e.request, resClone);
          });
          return response;
        })
        .catch(() => caches.match(e.request))
    );
  }
});
