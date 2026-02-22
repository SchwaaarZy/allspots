# AllSpots OSM Backend (Render)

Simple Node.js backend for OSM POIs.

## Endpoints

- `GET /health`
- `GET /poi?lat=...&lng=...&radius=...&categories=culture,nature,...`

## Render

Start Command:

```
node server.js
```

## Notes

- Uses Overpass API (public). Consider caching for production.
- OSM attribution is required in the app UI.
