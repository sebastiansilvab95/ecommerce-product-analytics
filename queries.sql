-- Analytical queries on a 2.1M-event e-commerce dataset (PostgreSQL).
-- Business question above each query, finding below. Comments in Spanish.

-- Query para refrescar memoria respecto a la información que tiene la tabla a analizar.

SELECT * FROM events LIMIT 5;

-- PREGUNTA: ¿Cuáles son las semanas con mayor cantidad de usuarios por tipo de evento?

SELECT 
	DATE_TRUNC('week', event_time) AS semana,
	event_type AS tipo_de_evento,
	COUNT(1) AS cantidad_eventos,
	COUNT(DISTINCT user_id) AS cantidad_usuarios
FROM events
GROUP BY semana, tipo_de_evento
ORDER BY semana, tipo_de_evento;

/* 
 HALLAZGO: La tercera semana concentra el máximo de vistas, carritos y usuarios únicos.
 Pero el dato que importa es otro: los carritos casi se duplican respecto a la semana anterior (7.486 → 15.043) sin que las vistas se muevan. Las compras, en cambio, se mantienen estables.
 Eso no se explica por comportamiento; apunta a un cambio en el registro del evento 'cart' y motiva la query siguiente.
 La última semana tiene menos eventos por tener menos días observados, no por menor actividad.
*/

-- PREGUNTA: ¿La caída del embudo refleja comportamiento de usuarios o un problema de registro de eventos? Si el comportamiento cambiara, las dos razones se moverían juntas.

SELECT
    DATE_TRUNC('week', event_time) AS semana,
    COUNT(*) FILTER (WHERE event_type = 'view')     AS vistas,
    COUNT(*) FILTER (WHERE event_type = 'cart')     AS carritos,
    COUNT(*) FILTER (WHERE event_type = 'purchase') AS compras,
    ROUND(100.0 * COUNT(*) FILTER (WHERE event_type = 'cart')
          / NULLIF(COUNT(*) FILTER (WHERE event_type = 'view'), 0), 2) AS carritos_por_vista_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE event_type = 'purchase')
          / NULLIF(COUNT(*) FILTER (WHERE event_type = 'view'), 0), 2) AS compras_por_vista_pct
FROM events
GROUP BY 1
ORDER BY 1;

/*
	HALLAZGO: Compras/vistas es plana todo el mes (1,67%–1,94%). Carritos/vistas se duplica entre la semana 2 y la 3 (1,57% → 3,08%) mientras las vistas se mantienen (476.875 → 488.735).
	Un cambio real de comportamiento movería ambas razones; solo se mueve una. El evento 'cart' es inestable, el embudo no. Por eso la tasa carro→compra no se reporta como conversión.
*/

-- PREGUNTA: ¿Cuántas categorías no registran ningún carrito, y cuántas compras hay detrás de ellas?

WITH por_categoria AS (
    SELECT
        category_code,
        COUNT(*) FILTER (WHERE event_type = 'view')     AS vistas,
        COUNT(*) FILTER (WHERE event_type = 'cart')     AS carritos,
        COUNT(*) FILTER (WHERE event_type = 'purchase') AS compras
    FROM events
    WHERE category_code IS NOT NULL
    GROUP BY 1
)
SELECT
    COUNT(*)                                  AS categorias,
    COUNT(*) FILTER (WHERE carritos = 0)      AS categorias_sin_carrito,
    SUM(vistas)  FILTER (WHERE carritos = 0)  AS vistas_sin_carrito,
    SUM(compras) FILTER (WHERE carritos = 0)  AS compras_sin_carrito
FROM por_categoria;

/*
	HALLAZGO: 43 de 126 categorías no registran ningún carrito, y aun así acumulan 112.543 vistas y 530 compras. No son "pocos" carritos: son cero exacto. Ropa es el caso más claro, 21 de sus 22 categorías no tienen un solo evento de carrito, y la restante tiene dos.
	Esto confirma que el problema es de instrumentación y no de comportamiento: un usuario puede saltarse el carrito ocasionalmente, pero no una categoría completa durante un mes entero.
	Nota de unidades: esta query cuenta EVENTOS. El embudo por categoría cuenta sesiones, por lo que las mismas 43 categorías equivalen ahí a ~34.600 pares sesión-categoría. No comparar cifras entre ambas unidades.
*/

-- PREGUNTA: ¿Cuáles son las categorías con mayor tasa de conversión?

SELECT
	category_code AS categoria,
	COUNT(*) FILTER (WHERE event_type = 'view') AS vistas,
	COUNT(*) FILTER (WHERE event_type = 'purchase') AS compras,
	ROUND(
		100.0 * COUNT(*) FILTER (WHERE event_type = 'purchase')
		/ NULLIF(COUNT(*) FILTER (WHERE event_type = 'view'), 0)
	, 2) AS tasa_conversion_pct
FROM events
WHERE category_code IS NOT NULL
GROUP BY 1
HAVING COUNT(*) FILTER (WHERE event_type = 'view') > 1000
ORDER BY 4 DESC;

/*
	HALLAZGO: electronics.smartphone concentra el 39,4% de las vistas categorizadas y es la de mayor conversión. El negocio, medido por tráfico, es esencialmente una tienda de smartphones.
	Un 30,2% adicional de las vistas no tiene category_code, así que dos tercios de la actividad son un solo producto o ninguno.

	CORRECCIÓN POSTERIOR: mi primera lectura fue que ropa convertía mal por oferta poco atractiva o por un problema en la página. El análisis por embudo mostró que 21 de las 22 categorías de ropa no registran un solo evento de carrito (la restante registra dos): la causa es que el evento no se dispara,
	no el producto. Dejo la conclusión original visible porque el error importa más que el acierto: una tasa de conversión baja puede ser un problema de negocio o un problema de medición, y no se distinguen sin mirar el evento intermedio.
*/

-- PREGUNTA: ¿Cuál es la retención por cohorte semanal?

WITH primera_actividad AS (
	SELECT 
		user_id,
		DATE_TRUNC('week', MIN(event_time)) AS semana_cohorte
	FROM events
	GROUP BY 1
),
actividad AS (
	SELECT DISTINCT
		user_id,
		DATE_TRUNC('week', event_time) AS semana_activa
	FROM events
),
tamano_cohorte AS (
	SELECT
		semana_cohorte,
		COUNT(*) AS usuarios_iniciales
	FROM primera_actividad 
	GROUP BY 1
)
SELECT
      p.semana_cohorte,
      FLOOR(EXTRACT(EPOCH FROM (a.semana_activa - p.semana_cohorte)) / 604800) AS semana_n,
      COUNT(DISTINCT a.user_id) AS usuarios_activos,
      ROUND(100.0 * COUNT(DISTINCT a.user_id) / t.usuarios_iniciales, 1) AS retencion_pct
  FROM primera_actividad p
  JOIN actividad a       ON a.user_id = p.user_id
  JOIN tamano_cohorte t  ON t.semana_cohorte = p.semana_cohorte
  GROUP BY 1, 2, t.usuarios_iniciales
  ORDER BY 1, 2;

/*
	HALLAZGO: Leída de forma directa, la retención de semana 1 cae de 35,9% a 12,2% entre la primera y la última cohorte. La lectura es incorrecta: ambos extremos están censurados.
	- Por la izquierda: el dataset empieza en la primera cohorte, así que todo cliente preexistente activo esa semana queda clasificado como nuevo. Los usuarios establecidos retienen mejor, lo que infla el 35,9% por construcción.
	- Por la derecha: la cohorte del 21-oct tiene su semana 1 entre el 28-oct y el 3-nov, pero los datos terminan el 31 → solo 4 de 7 días observados. El 12,2% está deprimido por construcción.
	La única comparación limpia son las dos cohortes centrales, ambas completamente observadas: 27,2% contra 22,5%. La caída existe, pero es de 5 puntos, no de 24.
*/


-- PREGUNTA: ¿Cuál es la tasa de conversión con cada paso del embudo?

WITH sesiones AS (
	SELECT
		user_session,
		MAX(CASE WHEN event_type = 'view'     THEN 1 ELSE 0 END) AS vio,
		MAX(CASE WHEN event_type = 'cart'     THEN 1 ELSE 0 END) AS agrego,
		MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS compro
	FROM events
	GROUP BY 1
)
SELECT
	COUNT(*) FILTER (WHERE vio = 1) AS paso1_vio,
	COUNT(*) FILTER (WHERE agrego = 1) AS paso2_carro,
	COUNT(*) FILTER (WHERE compro = 1) AS paso3_compro,
	ROUND(
		100.0 * COUNT(*) FILTER (WHERE agrego = 1)
		/ NULLIF(COUNT(*) FILTER (WHERE vio = 1), 0)
	, 2) AS conv_vista_a_carro_pct,
	ROUND(
		100.0 * COUNT(*) FILTER (WHERE compro = 1)
		/ NULLIF(COUNT(*) FILTER (WHERE agrego = 1), 0)
	, 2) AS conv_carro_a_compra_pct
FROM sesiones;

/*
	HALLAZGO: La conversión carro→compra da 108,61%, es decir más sesiones compran que agregan al carro. Es imposible como comportamiento, así que la trato como señal de instrumentación y no como métrica (ver la query de razones por semana y la de categorías sin carrito).
	El paso vista→carro, que no depende de la anomalía, sí es interpretable: solo el 6,26% de las sesiones que ven un producto muestran intención de compra. Ahí está el volumen perdido, no en el checkout.
*/

-- PREGUNTA: ¿Cuál es la tasa de conversión con cada paso del embudo por categoría?

WITH sesiones AS (
	SELECT
		category_code,
		user_session,
		MAX(CASE WHEN event_type = 'view'     THEN 1 ELSE 0 END) AS vio,
		MAX(CASE WHEN event_type = 'cart'     THEN 1 ELSE 0 END) AS agrego,
		MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS compro
	FROM events
	GROUP BY 1, 2
)
SELECT
	category_code,
	COUNT(*) FILTER (WHERE vio = 1) AS paso1_vio,
	COUNT(*) FILTER (WHERE agrego = 1) AS paso2_carro,
	COUNT(*) FILTER (WHERE compro = 1) AS paso3_compro,
	ROUND(
		100.0 * COUNT(*) FILTER (WHERE agrego = 1)
		/ NULLIF(COUNT(*) FILTER (WHERE vio = 1), 0)
	, 2) AS conv_vista_a_carro_pct,
	ROUND(
		100.0 * COUNT(*) FILTER (WHERE compro = 1)
		/ NULLIF(COUNT(*) FILTER (WHERE agrego = 1), 0)
	, 2) AS conv_carro_a_compra_pct
FROM sesiones
GROUP BY 1
ORDER BY 5 DESC;

/*
	HALLAZGO: Varias categorías registran compras sin ningún carrito. Esta query fue el punto de partida para investigarlo; la respuesta está en las dos queries de instrumentación de más arriba: el evento 'cart' no se dispara en 43 de las 126 categorías.
	Muchas categorías con vistas y sin compras, estas llevan para abajo el número.
	La categoría con mayor conversión es smartphone, teniendo muchísimas más vistas, aproximadamente un tercio de las vistas.
	La categoría smartphone la vería aparte respecto al global, ya que su cantidad de vistas y compras opaca a las otras categorías, ocultando el verdadero valor de conversión y dificultando el poder crear planes de acción al respecto.
	Nota metodológica: esta query agrupa por sesión Y categoría, así que una sesión que navega dos categorías se cuenta en ambas (561.617 pares sesión-categoría contra 458.901 sesiones reales). 
	La unidad de análisis es el par, no la sesión. Eso también implica que puede haber compra sin carrito en una categoría mientras el carrito existe en otra — efecto distinto del defecto global.
*/

-- PREGUNTA: ¿Cuánto pesa una sola categoría en el tráfico, y cuánta actividad no está
-- categorizada? Si una categoría domina el volumen, la conversión global la describe a ella
-- y no al catálogo.

WITH sesiones AS (
    SELECT
        user_session,
        category_code,
        MAX(CASE WHEN event_type = 'view' THEN 1 ELSE 0 END) AS vio,
        MAX(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS agrego
    FROM events
    GROUP BY 1, 2
),
clasificadas AS (
    SELECT
        CASE
            WHEN category_code IS NULL                       THEN 'sin_categoria'
            WHEN category_code = 'electronics.smartphone'    THEN 'smartphone'
            ELSE                                                  'resto_catalogo'
        END AS grupo,
        vio,
        agrego
    FROM sesiones
)
SELECT
    grupo,
    COUNT(*) FILTER (WHERE vio = 1) AS sesiones_con_vista,
    ROUND(100.0 * COUNT(*) FILTER (WHERE vio = 1)
          / SUM(COUNT(*) FILTER (WHERE vio = 1)) OVER (), 1) AS pct_del_total,
    ROUND(100.0 * COUNT(*) FILTER (WHERE agrego = 1)
          / NULLIF(COUNT(*) FILTER (WHERE vio = 1), 0), 2) AS conv_vista_a_carro_pct
FROM clasificadas
GROUP BY 1
ORDER BY 2 DESC;