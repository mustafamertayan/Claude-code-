// Kültürİz: ana ekrana eklenebilmesi ve internet yokken açılış sayfasının görünmesi için.
// Sunucudaki veriler (Supabase) önbelleğe alınmaz; her zaman canlı gelir.
var SURUM = "kulturiz-v1";
var KABUK = ["./", "index.html", "manifest.webmanifest", "assets/logo-isaret.png", "assets/simge-192.png", "assets/giris-arka.jpg"];

self.addEventListener("install", function (e) {
  e.waitUntil(caches.open(SURUM).then(function (c) { return c.addAll(KABUK); }).then(function () { return self.skipWaiting(); }));
});
self.addEventListener("activate", function (e) {
  e.waitUntil(caches.keys().then(function (ks) {
    return Promise.all(ks.filter(function (k) { return k !== SURUM; }).map(function (k) { return caches.delete(k); }));
  }).then(function () { return self.clients.claim(); }));
});
self.addEventListener("fetch", function (e) {
  var r = e.request, u = new URL(r.url);
  if (r.method !== "GET" || u.origin !== location.origin) return;
  // Önce ağ: site güncellenince hemen yeni hâli gelir; ağ yoksa önbellekten.
  e.respondWith(fetch(r).then(function (yanit) {
    if (yanit.ok && (r.mode === "navigate" || /\.(html|png|webmanifest|json)$/.test(u.pathname))) {
      var kopya = yanit.clone(); caches.open(SURUM).then(function (c) { c.put(r, kopya); });
    }
    return yanit;
  }).catch(function () {
    return caches.match(r).then(function (m) { return m || (r.mode === "navigate" ? caches.match("index.html") : undefined); });
  }));
});
