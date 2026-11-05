# Bodegas del Atuel

Trabajo Práctico Integrador de la cátedra **Bases de Datos** de la UTN Facultad Regional San Rafael (Ingeniería en Sistemas, 3.° año, ciclo 2026).

Sistema de gestión y distribución de una empresa vitivinícola. La base de datos es el corazón del proyecto: modelo, constraints, funciones, procedimientos, triggers, carga masiva, índices, consultas y API/front desplegados en la nube.

## Integrantes

| Rol | Responsable |
|---|---|
| P1 · Datos-Núcleo | (completar) |
| P2 · Datos-Volumen | Mateo Vergara |
| P3 · API | (completar) |
| P4 · Front e Infraestructura | (completar) |

## Stack

- PostgreSQL 16 (compatible con 14 o superior).
- Docker y Docker Compose.
- API REST con driver nativo y SQL directo (sin ORM).
- Front libre que consume únicamente la API.

## Requisitos

- Docker Engine con Docker Compose v2.
- `psql` opcional, para conectarse desde el host.
- Git.

## Arranque rápido

```bash
cp .env.example .env
docker compose up -d
```

La base queda disponible en `localhost:${POSTGRES_PORT}` (por defecto `5432`) con las credenciales definidas en `.env`.

Para recrear la base desde cero (borra el volumen y vuelve a aplicar las migraciones):

```bash
./scripts/reset_db.sh
```

## Estructura

```text
.
├── api/                  # API REST
├── consultas/            # Consultas SQL (insert, update, delete, select)
├── db/
│   ├── migrations/       # Migraciones en orden (001_esquema.sql, ...)
│   ├── seed/             # Catálogos y scripts de carga
│   └── tests/            # Pruebas de reglas de la base
├── docs/                 # DER, esquema, diccionario, informes y bocetos
├── front/                # Front que consume la API
├── scripts/              # Utilidades (reset, backup, restore, migraciones)
├── .env.example
├── docker-compose.yml
└── README.md
```

## Migraciones

Los archivos de `db/migrations/` se ejecutan en orden alfabético la primera vez que se crea el volumen de datos, porque la carpeta se monta en `/docker-entrypoint-initdb.d`.

Si cambiás una migración existente o agregás una nueva, recreá la base con:

```bash
./scripts/reset_db.sh
```

## Estado del proyecto

- [x] Fase 0 · Arranque común (P4: 0.1, 0.2, 0.6 y 0.7).
- [ ] Fase 1 · Modelado (H1).
- [ ] Fase 2 · Integridad y lógica (H2).
- [ ] Fase 3 · Carga masiva (H3).
- [ ] Fase 4 · Índices y rendimiento (H4).
- [ ] Fase 5 · Consultas SQL (H5).
- [ ] Fase 6 · API REST (H6).
- [ ] Fase 7 · Front (H7).
- [ ] Fase 8 · Despliegue en la nube (H8).
- [ ] Fase 9 · Documentación y defensa (H9).

## Primer commit de cada integrante

Cada integrante debe agregar su nombre en la tabla de integrantes y hacer su propio commit con su usuario de Git. Para no trabajar sobre `main` protegida:

```bash
git clone https://github.com/BenjaDiaZzZ/Bodegas-del-atuel.git
cd Bodegas-del-atuel
git switch -c docs/nombre-integrante
# editar README.md y reemplazar el "(completar)" del rol propio
git add README.md
git commit -m "docs: agrega nombre de <integrante>"
git push -u origin docs/nombre-integrante
```

Luego se abre un PR y lo revisa el siguiente integrante de la cadena P1 → P2 → P3 → P4 → P1.

## Documentación

- [Plan de trabajo y tablero](docs/tablero.md)
- [Informe · Arranque](docs/informe/00-arranque.md)
- [Informe · Nube](docs/informe/08-nube.md)
