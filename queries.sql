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

-- PREGUNTA: ¿Cuáles son los tres productos más comprados dentro de cada categoría?

WITH ventas AS (
	SELECT
		category_code,
		product_id,
		COUNT(*) AS compras
	FROM events
	WHERE event_type = 'purchase' AND category_code IS NOT NULL
	GROUP BY 1, 2
)
SELECT
	*
FROM (
	SELECT
		v.*,
		ROW_NUMBER() OVER (
						   PARTITION BY category_code
						   ORDER BY compras DESC
		                  ) AS ranking
	FROM ventas v	
) x
WHERE x.ranking <= 3
ORDER BY category_code, ranking;

/*
	HALLAZGO: Existen categorías que no tiene suficientes ventas para tener un top 3.
	electronics.smartphone es la categoría con mayor venta, el único que se le acerca es electronics.audio.headphone con el producto con mayor venta siendo casi un tercio del primero de smartphone.
*/

-- PREGUNTA: ¿Cuántas categorías no tienen productos suficientes para tener un top 3?

WITH ventas AS (
    SELECT
        category_code,
        product_id,
        COUNT(*) AS compras
    FROM events
    WHERE event_type = 'purchase' AND category_code IS NOT NULL
    GROUP BY 1, 2
)
SELECT
    COUNT(DISTINCT category_code) AS total_categorias,
    COUNT(DISTINCT category_code) FILTER (
        WHERE category_code IN (
            SELECT category_code
            FROM ventas
            GROUP BY category_code
            HAVING COUNT(DISTINCT product_id) < 3
        )
    ) AS categorias_sin_top3
FROM ventas;

/*
	HALLAZGO: electronics.smartphone es la categoría con más ventas: su producto líder (1.497 unidades) más que duplica al segundo lugar de todo el catálogo. 13 de 106 categorías no alcanzan a tener top 3
	por falta de productos distintos vendidos.
*/


-- PREGUNTA: ¿Cuál es el tiempo desde la primera vista hasta la compra en promedio?

WITH sesion AS (
	SELECT
		user_session,
		MIN(event_time) FILTER (WHERE event_type = 'view') AS primera_vista,
		MIN(event_time) FILTER (WHERE event_type = 'purchase') AS primera_compra
	FROM events
	GROUP BY 1
)
SELECT
	COUNT(*) AS sesiones_con_compra,
	ROUND(AVG(EXTRACT(EPOCH FROM (primera_compra - primera_vista)) / 60)::numeric, 1) AS minutos_promedio,
	ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (primera_compra - primera_vista)) / 60)::NUMERIC, 1) AS minutos_mediana
FROM sesion
WHERE primera_vista IS NOT NULL AND primera_compra IS NOT NULL;

/*
	HALLAZGO: El promedio es bastante superior a la mediana, por lo que exiten sesiones que se extendieron demasiado y mueven el promedio hacia arriba. Recomiendo usar la mediana para tener un estimado más accionable.
*/

-- PREGUNTA: ¿Qué sesiones agregaron productos al carro pero no compraron en esa misma sesión?

SELECT c.user_session, COUNT(*) AS items_agregados
FROM events c
WHERE c.event_type = 'cart'
  AND NOT EXISTS (
      SELECT 1 FROM events p
      WHERE p.user_session = c.user_session
        AND p.event_type = 'purchase'
  )
GROUP BY 1
ORDER BY 2 DESC
LIMIT 20;

/*
	HALLAZGO: La sesión que lidera agrega 118 ítems al carro sin ninguna compra. Ninguna navegación real genera esa cifra: es la misma señal de instrumentación defectuosa de la query de carritos vs. compras
	por semana, ahora visible a nivel de sesión individual en vez de agregada. No cambia la conclusión (el evento 'cart' no es confiable hasta corregirse), pero acota dónde buscar el origen del defecto.
*/

-- PREGUNTA: ¿Cuál es el porcentaje de las compras de cada producto en su categoría?

WITH ventas AS (
	SELECT
		category_code,
		product_id,
		COUNT(*) AS compras
	FROM events
	WHERE event_type = 'purchase' AND category_code IS NOT NULL
	GROUP BY 1,2
)
SELECT
	x.*
FROM (
	  SELECT
	  	v.category_code,
	  	v.product_id,
	  	v.compras,
    	SUM(v.compras) OVER(PARTITION BY category_code) AS total_categoria,
	  	ROUND(
	  		100.0 * v.compras / SUM(v.compras) OVER(PARTITION BY category_code)
	  		, 1) AS porcentaje
	  FROM ventas v
	 ) x
WHERE x.porcentaje >= 10
ORDER BY category_code, porcentaje DESC;

/*
	HALLAZGO: Existen productos que se llevan el 100% de su categoría (¿Propuestas poco atractivas o poca oferta de productos?).
	En las categorías relacionadas a tecnología está más proporcionado el porcentaje por producto, lo que podría significar mayor oferta o mayor competitividad entre los productos.
*/

-- PREGUNTA: ¿Cuál es el promedio de día entre compras de los usuarios que han hecho al menos dos compras?

WITH compras_por_dia AS (
	SELECT DISTINCT
		user_id,
		DATE(event_time) AS dia_compra
	FROM events
	WHERE event_type = 'purchase'
),
con_anterior AS (
	SELECT
		user_id,
		dia_compra,
		LAG(dia_compra) OVER(
						    PARTITION BY user_id
						    ORDER BY dia_compra
		   					) AS compra_anterior
	FROM compras_por_dia
)
SELECT
	user_id,
	COUNT(*) + 1 AS total_compras, -- +1 porque la primera fila no tiene "anterior"
	ROUND(AVG(dia_compra - compra_anterior), 1) AS dias_promedio_entre_compras
FROM con_anterior
WHERE compra_anterior IS NOT NULL
GROUP BY user_id
ORDER BY 2, dias_promedio_entre_compras ASC
LIMIT 20;

/*
	HALLAZGO: Los 20 usuarios con recompra más rápida están todos en exactamente 1 día de promedio.
	Esto es el extremo de la cola, no la tendencia general: el LIMIT 20 sobre un ORDER BY ascendente siempre muestra a los más veloces, no una muestra representativa. 
	Ver la query siguiente para el panorama completo.
*/

-- PREGUNTA: ¿Cuál es el promedio general de días entre compras, considerando a todos los usuarios con 2 o más compras, no solo a los más rápidos?

WITH compras_por_dia AS (
	SELECT DISTINCT
		user_id,
		DATE(event_time) AS dia_compra
	FROM events
	WHERE event_type = 'purchase'
),
con_anterior AS (
	SELECT
		user_id,
		dia_compra,
		LAG(dia_compra) OVER(
						    PARTITION BY user_id
						    ORDER BY dia_compra
		   					) AS compra_anterior
	FROM compras_por_dia
),
por_usuario AS (
	SELECT
		user_id,
		COUNT(*) + 1 AS total_compras,
		AVG(dia_compra - compra_anterior) AS dias_promedio
	FROM con_anterior
	WHERE compra_anterior IS NOT NULL
	GROUP BY user_id
)
SELECT
    COUNT(*) AS usuarios_con_2_o_mas_compras,
    ROUND(AVG(dias_promedio), 1) AS promedio_general_dias,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dias_promedio)::numeric, 1) AS mediana_dias
FROM por_usuario;

/*
	HALLAZGO: 4.567 usuarios registran 2 o más compras. El promedio general de días entre compras consecutivas es 6,1, mientras la mediana es 4,4: la misma asimetría hacia la derecha que aparece
	en el tiempo vista→compra, con una cola de recompradores lentos tirando el promedio hacia arriba.
	Con un mes de datos, este número está subestimado para usuarios cerca del inicio o el fin de la ventana, el mismo problema de censura de la retención por cohorte.
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
	La unidad de análisis es el par, no la sesión. Eso también implica que puede haber compra sin carrito en una categoría mientras el carrito existe en otra, efecto distinto del defecto global.
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

/*
	HALLAZGO: electronics.smartphone concentra 27,5% de las sesiones con vista pese a ser una sola categoría, y convierte a 10,99% vista→carro frente a 3,70% del resto del catálogo (~3x). El 30,2% adicional 
	sin category_code no puede analizarse por categoría. La tasa global de 6,26% mezcla estos tres grupos y no describe bien a ninguno.
*/