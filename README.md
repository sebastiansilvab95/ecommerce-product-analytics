# E-commerce Product Analytics

Análisis de comportamiento de usuarios sobre 2,1 millones de eventos de un
e-commerce multi-categoría: embudo de conversión, retención por cohorte y
recomendaciones de producto.

**Estado:** en desarrollo 🚧

## Datos

- **Fuente:** [eCommerce behavior data from multi-category store](https://www.kaggle.com/datasets/mkechinov/ecommerce-behavior-data-from-multi-category-store) (Kaggle)
- **Período analizado:** octubre 2019
- **Muestra:** 2.103.521 eventos · 150.357 usuarios · 459.000 sesiones
- **Muestreo:** 5% de los usuarios, conservando *todos* sus eventos.
  Se muestrea por usuario y no por fila para no romper los embudos ni las cohortes.

### Distribución de eventos

| Evento | Cantidad |
|---|---|
| view | 2.019.379 |
| cart | 47.156 |
| purchase | 36.986 |

Observación inicial: solo ~2,3% de las vistas llegan al carro, pero el 78% de
los eventos de carro terminan en compra. El cuello de botella está antes del
carro, no en el checkout. *(Métricas a nivel de evento; el análisis por sesión
puede diferir.)*

## Stack

PostgreSQL 16 (Docker) · Python · pandas · matplotlib

## Estructura

sql/ Queries de análisis
notebooks/ Análisis en Python
images/ Gráficos exportados
data/ Datos (no versionados)

## Cómo reproducirlo

1. Descargar `2019-Oct.csv` desde Kaggle y dejarlo en `data/`
2. Muestrear: `awk -F',' 'NR==1 || ($8 % 100 < 5)' 2019-Oct.csv > muestra.csv`
3. Levantar Postgres: `docker run --name pg-practica -e POSTGRES_PASSWORD=practica -p 5432:5432 -d postgres:16`
4. Crear la tabla y cargar los datos (ver `sql/setup.sql`)

## Hallazgos

*Por completar.*

## Recomendaciones

*Por completar.*