# 🏗️ Techno Analytics - Architecture Diagrams

Complete system architecture with data flow, infrastructure, and component interactions.

---

## 🌐 Complete System Architecture

```mermaid
graph TB
    subgraph "User Layer"
        User[👤 User<br/>iOS/Android/Web]
    end

    subgraph "Flutter App Layer"
        App[📱 Flutter App<br/>Dart 3.0+]

        subgraph "Views"
            Login[🔐 Login View]
            Dashboard[📊 Dashboard View]
            Explorer[🗺️ Explorer View]
            Config[⚙️ Config View]
        end

        subgraph "Services"
            SupaService[🔌 Supabase Service<br/>Database queries]
            RasterService[🎨 Modern Raster Service<br/>COG/TiTiler integration]
            WeatherService[🌤️ Weather Service<br/>Open-Meteo API]
        end

        subgraph "State"
            LocalState[💾 Local State<br/>StatefulWidget + setState]
            Cache[📦 SharedPreferences<br/>User session, weather cache]
        end
    end

    subgraph "Backend Infrastructure"
        subgraph "Supabase - Database"
            SupaDB[(🗄️ PostgreSQL<br/>Users, Products, Parcels)]
            SupaAuth[🔑 Supabase Auth<br/>JWT tokens]
            SupaAPI[🌐 Supabase REST API<br/>Auto-generated]
        end

        subgraph "Google Cloud Platform"
            GCS[☁️ Cloud Storage<br/>COG files storage]
            TiTiler[🖼️ TiTiler Service<br/>Cloud Run<br/>Auto-scale 0-10]
            CDN[🌍 Cloud CDN<br/>Global tile caching]
            LB[⚖️ Load Balancer<br/>Traffic distribution]
        end

        subgraph "External APIs"
            OpenMeteo[🌦️ Open-Meteo API<br/>Weather data]
            Mapbox[🗺️ Mapbox API<br/>Satellite basemap]
        end
    end

    subgraph "Data Processing Pipeline"
        LocalRaster[📂 Local GeoTIFF Files<br/>.tif rasters]
        Python[🐍 Python Scripts<br/>GDAL processing]
        COG[📊 Cloud Optimized GeoTIFF<br/>.cog.tif files]
    end

    %% User interactions
    User -->|Opens app| App
    App --> Login
    Login --> Dashboard
    Login --> Explorer
    Login --> Config

    %% View to Service connections
    Dashboard --> SupaService
    Dashboard --> WeatherService
    Explorer --> SupaService
    Explorer --> RasterService
    Explorer --> WeatherService

    %% Service to Backend
    SupaService -->|REST API| SupaAPI
    SupaAPI --> SupaDB
    SupaService -->|Auth| SupaAuth

    RasterService -->|Get metadata| SupaDB
    RasterService -->|Request tiles| LB

    WeatherService -->|Fetch weather| OpenMeteo
    Explorer -->|Base map| Mapbox

    %% Cache interactions
    SupaService -.->|Store session| Cache
    WeatherService -.->|Cache 1hr| Cache
    Dashboard -.->|Save filters| Cache

    %% GCP Infrastructure flow
    LB --> CDN
    CDN -->|Cache miss| TiTiler
    TiTiler -->|Read COG| GCS
    CDN -.->|Cache hit<br/>Fast response| Explorer

    %% Data processing pipeline
    LocalRaster -->|1. Convert| Python
    Python -->|GDAL| COG
    COG -->|2. Upload| GCS
    Python -->|3. Register metadata| SupaDB

    %% Styling
    classDef flutter fill:#02569B,stroke:#01579B,color:#fff
    classDef gcp fill:#4285F4,stroke:#1a73e8,color:#fff
    classDef supabase fill:#3ECF8E,stroke:#2da771,color:#fff
    classDef external fill:#FF6B6B,stroke:#ee5a52,color:#fff
    classDef data fill:#FFA500,stroke:#ff8c00,color:#fff

    class App,Login,Dashboard,Explorer,Config,SupaService,RasterService,WeatherService flutter
    class GCS,TiTiler,CDN,LB gcp
    class SupaDB,SupaAuth,SupaAPI supabase
    class OpenMeteo,Mapbox external
    class LocalRaster,Python,COG data
```

---

## 📊 Data Flow Diagram

```mermaid
flowchart LR
    subgraph "Data Sources"
        DB[(Supabase DB<br/>productos table)]
        GCS[☁️ GCS Bucket<br/>COG files]
    end

    subgraph "Flutter App Data Flow"
        UserAction[👤 User selects:<br/>Company, Ingenio,<br/>Date, Product]

        FetchMeta[📡 Fetch metadata<br/>getProductoInfo]

        ExtractData[📦 Extract:<br/>• cog_url<br/>• rescale_min/max<br/>• colormap<br/>• bounds]

        BuildURL[🔧 Build TiTiler URL<br/>buildTitilerTileUrl]

        TileRequest[🖼️ Request tiles<br/>/{z}/{x}/{y}.png]

        Render[✨ Render on map<br/>FlutterMap widget]
    end

    subgraph "Backend Processing"
        TiTiler[🎨 TiTiler Service<br/>Cloud Run]
        CDN[🌍 CDN Cache<br/>1 hour TTL]
    end

    %% Flow connections
    UserAction --> FetchMeta
    FetchMeta --> DB
    DB --> ExtractData
    ExtractData --> BuildURL
    BuildURL --> TileRequest
    TileRequest --> CDN
    CDN -->|Cache hit| Render
    CDN -->|Cache miss| TiTiler
    TiTiler --> GCS
    GCS --> TiTiler
    TiTiler --> CDN
    CDN --> Render

    %% Styling
    classDef action fill:#FFE66D,stroke:#f4d03f
    classDef process fill:#4ECDC4,stroke:#45b7aa
    classDef backend fill:#FF6B6B,stroke:#ee5a52

    class UserAction action
    class FetchMeta,ExtractData,BuildURL,TileRequest,Render process
    class TiTiler,CDN backend
```

---

## 🔄 Data Transformation Pipeline

```mermaid
flowchart TD
    subgraph "Data Ingestion Pipeline"
        A[📂 Raw GeoTIFF<br/>NDVI, NDWI, SG, etc.<br/>Any projection]

        B[🔍 Validation<br/>Check format,<br/>georeferencing]

        C[🔧 GDAL Conversion<br/>gdal_translate<br/>-of COG -co COMPRESS=LZW]

        D[📊 Cloud Optimized GeoTIFF<br/>Tiled, overviews,<br/>EPSG:4326]

        E[📤 Upload to GCS<br/>Public read access<br/>CORS enabled]

        F[📝 Extract Metadata<br/>Bounds, min/max,<br/>EPSG, nodata]

        G[(💾 Store in Supabase<br/>productos table<br/>cog_url, bounds, etc.)]
    end

    subgraph "App Consumption"
        H[📱 Flutter App<br/>Requests product]

        I[🔍 Query Database<br/>getProductoInfo]

        J[🎨 Build Tile URL<br/>+ colormap + rescale]

        K[🖼️ TiTiler generates<br/>PNG tiles on-demand]

        L[🌍 CDN caches tiles<br/>Fast delivery]

        M[✨ Render on map<br/>User sees imagery]
    end

    A --> B
    B --> C
    C --> D
    D --> E
    E --> F
    F --> G

    G -.->|Available for queries| I
    H --> I
    I --> J
    J --> K
    K --> L
    L --> M

    %% Styling
    classDef ingest fill:#3498db,stroke:#2980b9,color:#fff
    classDef consume fill:#2ecc71,stroke:#27ae60,color:#fff

    class A,B,C,D,E,F,G ingest
    class H,I,J,K,L,M consume
```

---

## 📊 Dashboard Data Aggregation Flow

```mermaid
flowchart TD
    subgraph "Data Source"
        A[(Supabase<br/>parcelas_ingenios table)]
    end

    subgraph "Data Loading"
        B[📡 Fetch parcels<br/>by empresa + ingenio]
        C[📦 List of parcels<br/>~1000-15000 records]
    end

    subgraph "Transformations"
        D[➕ Sum area_calculada<br/>→ haMonitoreo]

        E[🔍 Filter by fecha_fin<br/>→ haCosechadas]

        F[➕ Sum ton_real<br/>→ toneladasIndustrializadas]

        G[📅 Parse fecha_fin<br/>→ Calculate week number]

        H[📊 Group by week<br/>→ haPorSemana Map]

        I[🧮 Weighted average TCH<br/>→ tchPorSemana Map]

        J[🏆 Sort & Top 7<br/>→ Variety distribution]

        K[📈 Calculate yields<br/>→ Zone ranking]
    end

    subgraph "Visualization"
        L[📊 Bar Charts<br/>FL Chart]
        M[🎯 Radial Gauge<br/>Syncfusion]
        N[📈 Stacked Bars<br/>Custom widget]
        O[💳 Metric Cards<br/>Formatted numbers]
    end

    A --> B
    B --> C

    C --> D
    C --> E
    C --> F
    C --> G

    D --> O
    E --> O
    F --> O

    G --> H
    H --> I

    C --> J
    C --> K

    I --> L
    H --> L
    O --> M
    J --> N
    K --> N

    %% Styling
    classDef source fill:#3498db,stroke:#2980b9,color:#fff
    classDef transform fill:#e74c3c,stroke:#c0392b,color:#fff
    classDef viz fill:#2ecc71,stroke:#27ae60,color:#fff

    class A source
    class B,C source
    class D,E,F,G,H,I,J,K transform
    class L,M,N,O viz
```

---

## 🗺️ Map Rendering Architecture

```mermaid
flowchart TD
    subgraph "Map Layers Stack"
        Layer1[🌍 Layer 1: Satellite Base<br/>Mapbox tiles<br/>OSM alternative]

        Layer2[🎨 Layer 2: COG Raster<br/>TiTiler tiles<br/>NDVI, NDWI, SG, etc.]

        Layer3[📐 Layer 3: Field Parcels<br/>GeoJSON Polygons<br/>zoom >= 10]

        Layer4[📍 Layer 4: Inspections<br/>Marker clusters<br/>Photo points]
    end

    subgraph "Layer 2 Processing"
        A[📡 Get product info<br/>empresa, ingenio,<br/>producto, fecha]

        B[(Supabase<br/>productos table)]

        C[📦 Metadata:<br/>cog_url, colormap,<br/>rescale_min/max]

        D[🔧 Build tile URL<br/>TiTiler endpoint]

        E[🖼️ TileLayer widget<br/>urlTemplate with {z}/{x}/{y}]
    end

    subgraph "Layer 3 Processing"
        F[📡 Get parcels<br/>empresa + ingenio]

        G[(Supabase<br/>parcelas_ingenios)]

        H[📦 GeoJSON data:<br/>geometry_polygon field]

        I[🔄 Parse JSON<br/>Extract coordinates<br/>[[lng,lat],...]]

        J[🔀 Convert to LatLng<br/>Swap to [lat,lng]<br/>Validate bounds]

        K[📐 Create Polygons<br/>Flutter Map widgets<br/>Max 100 points each]

        L[✅ Check zoom level<br/>Render if zoom >= 10]
    end

    subgraph "Rendering"
        M[🗺️ FlutterMap Widget<br/>Combines all layers]

        N[✨ Display on screen<br/>Pan, zoom, interact]
    end

    %% Layer connections
    Layer1 --> M
    Layer2 --> M
    Layer3 --> M
    Layer4 --> M

    %% Layer 2 flow
    A --> B
    B --> C
    C --> D
    D --> E
    E --> Layer2

    %% Layer 3 flow
    F --> G
    G --> H
    H --> I
    I --> J
    J --> K
    K --> L
    L --> Layer3

    M --> N

    %% Styling
    classDef layer fill:#3498db,stroke:#2980b9,color:#fff
    classDef process fill:#e74c3c,stroke:#c0392b,color:#fff
    classDef db fill:#2ecc71,stroke:#27ae60,color:#fff
    classDef render fill:#9b59b6,stroke:#8e44ad,color:#fff

    class Layer1,Layer2,Layer3,Layer4 layer
    class A,C,D,E,F,H,I,J,K,L process
    class B,G db
    class M,N render
```

---

## 🏗️ Infrastructure & Cost Breakdown

```mermaid
graph TB
    subgraph "Google Cloud Platform - $20-50/month"
        GCS["☁️ Cloud Storage<br/>$1-2/month<br/>50GB COG files<br/>$0.02/GB"]

        CR["🖼️ Cloud Run<br/>$5-20/month<br/>TiTiler service<br/>Auto-scale 0-10"]

        CDN["🌍 Cloud CDN<br/>$8-15/month<br/>100GB egress<br/>$0.08-0.12/GB"]

        LB["⚖️ Load Balancer<br/>$5-7/month<br/>Forwarding rules<br/>$0.025/hour"]
    end

    subgraph "Supabase - $0-25/month"
        DB["💾 PostgreSQL<br/>Free: 500MB<br/>Pro: $25 (8GB)<br/>Unlimited API requests"]

        Auth["🔑 Authentication<br/>Included<br/>JWT tokens"]
    end

    subgraph "Free Tier Services"
        OM["🌤️ Open-Meteo<br/>FREE<br/>Non-commercial use<br/>10k requests/day"]

        MB["🗺️ Mapbox<br/>FREE tier<br/>50k map views/month<br/>$0.50/1k after"]
    end

    subgraph "Flutter App - Development Only"
        App["📱 Flutter App<br/>No hosting cost<br/>iOS/Android/Web builds<br/>Distributed via stores"]
    end

    %% Cost comparison
    Legacy["❌ Legacy GeoServer<br/>$150-250/month<br/>Always-on VM<br/>Manual scaling<br/>High maintenance"]

    Modern["✅ Modern Architecture<br/>$20-70/month<br/>Auto-scaling<br/>Serverless<br/>Low maintenance<br/><br/>💰 75-85% SAVINGS"]

    %% Connections
    App --> DB
    App --> CDN
    App --> OM
    App --> MB

    CDN --> CR
    CR --> GCS
    CR --> DB

    Legacy -.->|vs| Modern

    %% Styling
    classDef gcp fill:#4285F4,stroke:#1a73e8,color:#fff
    classDef supabase fill:#3ECF8E,stroke:#2da771,color:#fff
    classDef free fill:#00D084,stroke:#00b572,color:#fff
    classDef savings fill:#FFD700,stroke:#FFA500,color:#000
    classDef old fill:#FF6B6B,stroke:#ee5a52,color:#fff

    class GCS,CR,CDN,LB gcp
    class DB,Auth supabase
    class OM,MB free
    class Modern savings
    class Legacy old
```

---

## 🔐 Authentication & Authorization Flow

```mermaid
sequenceDiagram
    participant U as 👤 User
    participant App as 📱 Flutter App
    participant SP as 💾 SharedPreferences
    participant Supa as 🗄️ Supabase
    participant API as 🌐 REST API

    U->>App: Enter credentials
    App->>Supa: POST /auth/login<br/>email, password

    alt Valid credentials
        Supa-->>App: ✅ User data<br/>(company, ingenio, role)
        App->>SP: Store session<br/>user_company, user_ingenio,<br/>is_logged_in=true
        App-->>U: Redirect to Dashboard

        loop App usage
            U->>App: Request data
            App->>SP: Get session info
            SP-->>App: user_company, user_ingenio
            App->>API: Query with filters<br/>?empresa=X&ingenio=Y
            API->>Supa: SELECT with filters
            Supa-->>API: Filtered results
            API-->>App: JSON response
            App-->>U: Display data
        end
    else Invalid credentials
        Supa-->>App: ❌ Error
        App-->>U: Show error message
    end

    U->>App: Logout
    App->>SP: Clear session
    SP-->>App: ✅ Cleared
    App-->>U: Redirect to Login
```

---

## 📈 Performance & Scaling Architecture

```mermaid
graph TB
    subgraph "Client Layer - Millions of users possible"
        C1[📱 User 1<br/>Guatemala]
        C2[📱 User 2<br/>USA]
        C3[📱 User 3<br/>Brazil]
        C4[📱 User N<br/>Global]
    end

    subgraph "CDN Layer - Edge Caching"
        E1[🌍 CDN Edge<br/>us-central1]
        E2[🌍 CDN Edge<br/>southamerica-east1]
        E3[🌍 CDN Edge<br/>Global PoPs]
    end

    subgraph "Compute Layer - Auto-scaling"
        T1[🖼️ TiTiler Instance 1<br/>Active]
        T2[🖼️ TiTiler Instance 2<br/>Warm]
        T3[🖼️ TiTiler Instance N<br/>Auto-spawned]
        T0[💤 Scale to Zero<br/>When idle]
    end

    subgraph "Storage Layer - Unlimited"
        GCS[☁️ Google Cloud Storage<br/>Multi-region<br/>99.95% availability<br/>Unlimited capacity]
    end

    subgraph "Database Layer - Managed"
        DB[(💾 Supabase PostgreSQL<br/>Connection pooling<br/>Read replicas<br/>Auto backups)]
    end

    %% Traffic flow
    C1 --> E1
    C2 --> E2
    C3 --> E2
    C4 --> E3

    E1 -->|Cache miss| T1
    E2 -->|Cache miss| T2
    E3 -->|High load| T3

    T1 --> GCS
    T2 --> GCS
    T3 --> GCS

    T1 -.->|Low traffic| T0
    T2 -.->|No requests| T0

    T1 --> DB
    T2 --> DB
    T3 --> DB

    %% Performance metrics
    Metrics["📊 Performance Metrics<br/><br/>✅ Tile response: 50-200ms (cached)<br/>✅ Tile generation: 200-500ms (cold)<br/>✅ Database queries: 100-300ms<br/>✅ CDN cache hit rate: 85-95%<br/>✅ Auto-scale: 0-10 instances<br/>✅ Cold start: ~2 seconds<br/>✅ 99.9% uptime SLA"]

    %% Styling
    classDef client fill:#3498db,stroke:#2980b9,color:#fff
    classDef cdn fill:#e74c3c,stroke:#c0392b,color:#fff
    classDef compute fill:#2ecc71,stroke:#27ae60,color:#fff
    classDef storage fill:#f39c12,stroke:#d68910,color:#fff
    classDef metrics fill:#9b59b6,stroke:#8e44ad,color:#fff

    class C1,C2,C3,C4 client
    class E1,E2,E3 cdn
    class T1,T2,T3,T0 compute
    class GCS,DB storage
    class Metrics metrics
```

---

## 🔄 Complete Request Lifecycle

```mermaid
sequenceDiagram
    participant U as 👤 User
    participant F as 📱 Flutter App
    participant S as 🗄️ Supabase
    participant C as 🌍 CDN
    participant T as 🖼️ TiTiler
    participant G as ☁️ GCS

    Note over U,G: Step 1: User Action
    U->>F: Pan/Zoom map
    F->>F: Calculate visible tiles<br/>zoom=12, tiles={(x,y),...}

    Note over U,G: Step 2: Fetch Metadata
    F->>S: GET /productos?empresa=X&ingenio=Y&producto=ndvi&fecha=2024-01-15
    S-->>F: {cog_url: "gs://bucket/file.cog.tif",<br/>rescale_min: 0.0, rescale_max: 1.0}

    Note over U,G: Step 3: Build Tile URLs
    F->>F: buildTitilerTileUrl()<br/>url=gs://..., colormap=ndvi, rescale=0.0,1.0
    F->>F: Generate 20 tile URLs for visible area

    Note over U,G: Step 4: Request Tiles (parallel)
    par Tile 1
        F->>C: GET /cog/tiles/12/1024/2048.png?url=...
        alt Cache Hit (85-95% of requests)
            C-->>F: ✅ PNG tile (cached)<br/>~50ms
        else Cache Miss
            C->>T: Forward request
            T->>G: Read COG data<br/>Range: bytes=X-Y
            G-->>T: Byte range
            T->>T: Apply colormap<br/>Rescale values<br/>Generate PNG
            T-->>C: PNG tile<br/>~200-500ms
            C->>C: Cache tile (1 hour)
            C-->>F: PNG tile
        end
    and Tile 2
        F->>C: GET /cog/tiles/12/1024/2049.png?url=...
        C-->>F: PNG tile
    and Tile 3-20
        F->>C: GET /cog/tiles/...
        C-->>F: PNG tiles
    end

    Note over U,G: Step 5: Render
    F->>F: Compose tiles into map
    F-->>U: Display updated map view

    Note over U,G: Performance Summary
    Note over F: Total time: 100-800ms<br/>Cached: 100-300ms<br/>Uncached: 500-800ms
```

---

## 📝 Architecture Decision Records

### Why Cloud Optimized GeoTIFF (COG)?

```mermaid
graph LR
    A[Traditional GeoTIFF] -->|Problems| B[❌ Must download entire file<br/>❌ No partial reads<br/>❌ Slow for large files<br/>❌ Expensive bandwidth]

    C[Cloud Optimized GeoTIFF] -->|Benefits| D[✅ HTTP Range requests<br/>✅ Read only needed tiles<br/>✅ Fast partial access<br/>✅ Efficient streaming]

    B -.->|Solution| C

    style A fill:#FF6B6B,stroke:#ee5a52
    style B fill:#FFA07A,stroke:#ff7f50
    style C fill:#90EE90,stroke:#32CD32
    style D fill:#98FB98,stroke:#00FA9A
```

### Why TiTiler vs GeoServer?

| Feature | GeoServer | TiTiler |
|---------|-----------|---------|
| **Cost** | $150-250/month | $20-50/month |
| **Scaling** | Manual VM sizing | Auto 0-10 instances |
| **Maintenance** | High (updates, security) | Low (managed service) |
| **Cold Start** | Always warm (expensive) | ~2 seconds (acceptable) |
| **Format Support** | Many formats | COG optimized |
| **Performance** | Good | Excellent with CDN |

---

## 📚 Diagram Legend

| Symbol | Meaning |
|--------|---------|
| 🗄️ | Database |
| ☁️ | Cloud Storage |
| 📱 | Mobile App |
| 🖼️ | Image/Tile Service |
| 🌍 | CDN/Global Distribution |
| 🔐 | Authentication |
| 📊 | Data Processing |
| 🎨 | Rendering/Visualization |
| ⚖️ | Load Balancing |
| 💾 | Caching |

---

**Diagrams Version**: 1.0
**Last Updated**: 2024
**Total Diagrams**: 9

To render these diagrams:
1. Copy any diagram code block
2. Paste into [Mermaid Live Editor](https://mermaid.live)
3. Or view directly in GitHub README/documentation

