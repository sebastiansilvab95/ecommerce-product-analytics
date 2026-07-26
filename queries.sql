-- Query para resfrecar memoria respecto a la información que tiene la tabla a analizar.

SELECT * FROM events LIMIT 5;

-- EJERCICIO: Por cada event_type, muéstrame cuántos eventos hubo en total y cuántos usuarios distintos los generaron. Ordénalo por cantidad de eventos, de mayor a menor.

SELECT
	event_type AS tipo_evento,
	COUNT(*) AS cantidad_eventos,
	COUNT(DISTINCT user_id) AS cantidad_usuarios
FROM events
GROUP BY 1
ORDER BY 2 DESC;

-- HALLAZAGO: Llama la atención que haya más compradores únicos que usuarios con carro; antes de concluir nada, revisaría a nivel de usuario si de verdad hay compras sin evento cart previo, porque puede ser una característica de cómo el dataset registra los eventos, no un comportamiento real.

-- EJERCICIO: Dame las 5 marcas (brand) con más compras. Deja fuera las filas donde brand no tiene valor. Y muéstrame solo marcas que tengan más de 50 compras.

SELECT
	brand AS marca,
	COUNT(*) FILTER (WHERE event_type = 'purchase') AS ventas
FROM events
WHERE brand IS NOT NULL
GROUP BY brand
HAVING COUNT(*) FILTER (WHERE event_type = 'purchase') > 50
ORDER BY ventas DESC
LIMIT 5;

-- HALLAZGO: La marca con mayor ventas es Samsung.

-- EJERCICIO: Por cada día, cuántos usuarios únicos compraron. Ordenado por fecha.

SELECT
	DATE(event_time) AS fecha,
	COUNT(DISTINCT user_id) AS compras
FROM events
WHERE event_type = 'purchase'
GROUP BY 1
ORDER BY 1 ASC;

-- HALLAZGO: El primer día es el último día de septiembre, con muy poca venta (sin información de día completo?). Los primero y últimos días del mes tienen menor venta que los que están a mediados de mes.


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
 HALLAZGO: La segunda semana se tiene más venta con respecto a la primero, teniendo menor cantidad de carritos. 
 La tercera semana fue la semana con mayor cantidad de vistas, carritos y ventas, al igual que usuarios únicos.
 La semana dos tuvo menos usuarios únicos que la cuarta y tuvo mayor cantidad de vistas, o sea una mayor retención de su tiempo.
 La última semana fue la que tuvo menos eventos, pero se asume que es por tener menos días para transaccionar.
*/

-- PREGUNTA: ¿Qué categorias tiene mayor tasa de conversión?

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
	HALLAZAGO: La categoría electronics.smartphone es la que tiene mayor tasa de conversión, además de ser la que tiene más vistas y compras. Se podría entender que es lo que hace atractivo al negocio, su principal producto.
	La ropa es lo que tiene menor tasa de conversión, siendo algunas categorías sin ventas, tal vez se pudiese plantear el no seguir con esas categorías o si la forma en la que se presenta es poco atractiva. También da la sensación de que puede haber problemas técnicos con esa categoría en la página.
	La electronica es el fuerte del negocio.
	Zapatos con muchas visitas pero poca conversión, tal vez la oferta de productos no es atractiva.
	En general la tasa de conversión de visitas a compras no es tan alta en ninguna categoría especifica, habría que revisar el funnel completo para ver donde podría mejorarse o si hay productos que bajen esta tasa.
**/


	