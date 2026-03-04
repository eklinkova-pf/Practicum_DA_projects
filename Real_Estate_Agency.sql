/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 * 
 * Автор: Клинкова Екатерина
 * Дата: 12.05.2025
*/

-- Пример фильтрации данных от аномальных значений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдем id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    )
-- Выведем объявления без выбросов:
SELECT *
FROM real_estate.flats
WHERE id IN (SELECT * FROM filtered_id);


-- Задача 1: Время активности объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. Какие сегменты рынка недвижимости Санкт-Петербурга и городов Ленинградской области 
--    имеют наиболее короткие или длинные сроки активности объявлений?
-- 2. Какие характеристики недвижимости, включая площадь недвижимости, среднюю стоимость квадратного метра, 
--    количество комнат и балконов и другие параметры, влияют на время активности объявлений? 
--    Как эти зависимости варьируют между регионами?
-- 3. Есть ли различия между недвижимостью Санкт-Петербурга и Ленинградской области по полученным результатам?

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,           -- 99 процентиль по общей площади
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,                     -- 99 процентиль по количества комнат 
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,                 -- 99 процентиль по количеству балконов
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h, -- 99 процентиль по высоте потолков
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l  -- 1 процентиль по высоте потолков
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id                                        -- id квартир, после фильтрации 1 и 99 процентилем 
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Добавим категории Санкт-Петербург/ЛенОбл, ограничем по типу город:
filtered_region as (
SELECT 
	f.id,                                           -- id объявления
	f.total_area,                                   -- общая площадь квартиры
	f.rooms,                                        -- количество комнат 
	f.balcony,                                      -- количество балконов
	f.floor,                                        -- этаж 
	f.is_apartment,                                 -- признак Апартаменты
	f.ceiling_height,                               -- высота потолка
	f.parks_around3000,
	case 
		when c.city = 'Санкт-Петербург' then 'Санкт-Петербург'
		else 'ЛенОбл'
	end as region  -- фильтр по региону
FROM real_estate.flats as f
join real_estate.city as c on c.city_id = f.city_id
join real_estate.type as t on t.type_id = f.type_id
WHERE id IN (SELECT * FROM filtered_id) and type = 'город'
),
-- Добавим категорию по длительности размещения объявления (месяц/квартал/полгода/другие):
filtered_time as (
select 
	ft.id,                                         -- id объявления
	ft.total_area,                                 -- общая площадь квартиры
	ft.region,                                     -- регион
	ft.rooms,                                      -- количество комнат
	ft.balcony,                                    -- количество балконов
	ft.floor,                                      -- этаж
	ft.ceiling_height,                             -- высота потолка
	ft.is_apartment,                               -- признак Апартаменты
	ft.parks_around3000,
	a.days_exposition,                             -- длительность нахождения объявления на сайте (в днях)
	case
			when a.days_exposition <= 30 then '1_Месяц'
			when a.days_exposition > 30 and a.days_exposition <= 90 then '2_Квартал'
			when a.days_exposition > 90 and a.days_exposition <= 180 then '3_Полгода'
			when a.days_exposition > 180 then '4_Более полугода'
			else 'other'                           -- незакрытые объявленения/непроданные квартиры
	end as time_category,                          -- категория по времени размещения объявления
	last_price/total_area as one_meter_price       -- цена за один квадратный метр
from filtered_region as ft
join real_estate.advertisement as a on ft.id = a.id
),
-- Статистика:
stat as (
select 
	region,                                                                 -- регион: Санкт-Петербург/ЛенОбл
	time_category,                                                          -- временной интервал, когда объявление было размещено: месяц/квартал/полгода  
	min(days_exposition) as min_days_exposition,                            -- минимальная длительность нахождения объявления на сайте (в днях)
	max(days_exposition) as max_days_exposition,                            -- максимальная длительность нахождения объявления на сайте (в днях)
	avg(days_exposition) as avg_days_exposition,                            -- средняя длительность нахождения объявления на сайте (в днях)
	count(id) as count_advertisement,                                       -- количество объявлений
	round(avg(one_meter_price)::decimal,2) as avg_one_meter_price,          -- средняя цена за квадратный метр
	round(avg(total_area)::decimal,2) as avg_total_area,                    -- средняя площадь   
	percentile_disc(0.5) WITHIN GROUP (ORDER BY rooms) as median_rooms,     -- медиана по количеству комнат
	percentile_disc(0.5) WITHIN GROUP (ORDER BY balcony) as median_balcony, -- медиана по количеству балконов
	percentile_disc(0.5) WITHIN GROUP (ORDER BY floor) as median_floor,     -- медиана по этажу
	sum(is_apartment) as count_apartments,                                  -- количество апартаментов
	avg(ceiling_height) as avg_ceiling_height,                              -- средняя высота потолка
	percentile_disc(0.5) WITHIN GROUP (ORDER by parks_around3000) as median_parks_around3000
from filtered_time
group by region, time_category
having time_category <> 'other'
order by region desc
)
-- Основной запрос:
select 
	region,                                                          -- регион: Санкт-Петербург/ЛенОбл
	time_category,                                                   -- временной интервал, когда объявление было размещено: месяц/квартал/полгода
	count_advertisement,                                             -- количество объявлений в разбивке по временным сегментам
	sum(count_advertisement) 
		over (partition by region) as count_adv_by_region,           -- количество объявлений в разбивке по региону           
	round(count_advertisement::decimal*100/sum(count_advertisement) 
		over (partition by region),2) as perc_adv,                   -- процент объявлений по временным сегментам к общему кол-ву объявлениям по региону
	min_days_exposition,                                             -- минимальная длительность нахождения объявления на сайте (в днях)
	max_days_exposition,                                             -- максимальная длительность нахождения объявления на сайте (в днях)
	count_apartments,                                                -- количество апартаментов в разбивке по временным сегментам
	round(count_apartments::decimal*100/ sum(count_advertisement) 
		over (partition by region),2) as perc_apart,                 -- процент апартаментов по временным сегментам к общему кол-ву объявлениям по региону
	round(avg_one_meter_price::decimal,2) as avg_one_meter_price,    -- средняя цена за квадратный метр       
	round(avg_total_area::decimal,2) as avg_total_area,              -- средняя общая площадь квартиры
	round(avg_ceiling_height::decimal,2) as avg_ceiling_height,      -- средняя высота потолков
	median_rooms,                                                    -- медиана по количеству комнат
	median_balcony,                                                  -- медиана по количеству балконов
	median_floor,                                                     -- медиана по этажу квартиры
	median_parks_around3000
from stat
order by region desc, time_category asc;

-- Задача 2: Сезонность объявлений
-- Результат запроса должен ответить на такие вопросы:
-- 1. В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
--    А в какие — по снятию? Это показывает динамику активности покупателей.
-- 2. Совпадают ли периоды активной публикации объявлений и периоды, 
--    когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений)?
-- 3. Как сезонные колебания влияют на среднюю стоимость квадратного метра и среднюю площадь квартир? 
--    Что можно сказать о зависимости этих параметров от месяца?

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,           -- 99 процентиль по общей площади
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,                     -- 99 процентиль по количества комнат 
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,                 -- 99 процентиль по количеству балконов
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h, -- 99 процентиль по высоте потолков
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l  -- 1 процентиль по высоте потолков
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id                                                                      -- id квартир, после фильтрации 1 и 99 процентилем 
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- Информация об объявлении о продажи без выбросов:
data_for_stat_sale as(
	SELECT
		a.id as sale_id,                                                           -- id объявления
		a.first_day_exposition,                                                    -- дата размещения объявления
		extract (month from (first_day_exposition::date)) as month,                -- месяц размещения объявления
		a.last_price/f.total_area as sale_one_meter_price,                         -- цена за один квадратный метр
		f.total_area as sale_total_area                                            -- общая площадь квартиры
	FROM real_estate.flats as f
	join real_estate.type t on t.type_id = f.type_id
	join real_estate.advertisement as a on a.id = f.id
	WHERE 
		f.id IN (SELECT * FROM filtered_id)
		and extract (year from (first_day_exposition::date)) between 2015 and 2018 -- ограничиваем выборку 2015 - 2018 годами
		and type = 'город'                                                         -- ограничиваем выборку типов населенного пункта 'город'
),
-- Статистика по продажам:
sale_stat as (
select 
	month,                                                                         -- месяц размещения объявления
	count(sale_id) as sale_total_adv,                                              -- количество объявлений о продаже
	round(avg(sale_one_meter_price)::decimal,2) as sale_avg_one_meter_price,       -- средняя стоимость одного квадратного метра в обявлении о продажи
	round(avg(sale_total_area)::decimal,2) as sale_avg_total_area,                 -- средняя площадь квартиры в объявлении о продаже
	rank() over (order by count(sale_id) desc) as sale_rank_month                  -- ранк месяца, в зависимости от количества объявлений о продаже
from data_for_stat_sale
group by month
order by month
),
-- Информация об объявлении о покупки без выбросов:
data_for_stat_buy as(
	SELECT 
		a.id as buy_id,                                                                    -- id снятого с продажи объявления
		extract (month from (first_day_exposition::date + days_exposition::int)) as month, -- месяц снятия объявления с продажи
		a.last_price/f.total_area as buy_one_meter_price,                                  -- цена одного квадратного метра в снятом объявлении о продаже
		f.total_area as buy_total_area                                                     -- общая площадь квартиры в снятом объявлении о продаже
	FROM real_estate.flats as f
	join real_estate.type t on t.type_id = f.type_id
	join real_estate.advertisement as a on a.id = f.id
	WHERE 
		f.id IN (SELECT * FROM filtered_id)
		and days_exposition is not null                                                     -- выбираем объявления, которые были закрыты (поле должно быть заполнено)
		and extract (year from (first_day_exposition::date + days_exposition::int))         -- ограничиваем выборку 2015 - 2018 годами
			between 2015 and 2018
		and type = 'город'                                                                  -- ограничиваем выборку типов населенного пункта 'город'
),
-- Статистика по покупкам:
buy_stat as (
	select 
		month,                                                                              -- месяц снятия объявления с продажи                                         
		count(buy_id) as buy_total_adv,                                                     -- количество объявлений, снятых с продажи
		round(avg(buy_one_meter_price)::decimal,2) as buy_avg_one_meter_price,              -- средняя цена одного квадратного метра в снятом объявлении о продаже
		round(avg(buy_total_area)::decimal,2) as buy_avg_total_area,                        -- средняя общая площадь квартиры в снятом объявлении о продаже
		rank() over (order by count(buy_id) desc) as buy_rank_month                         -- ранк месяца, в зависимости от количества снятых объявлений о продаже
	from data_for_stat_buy
	group by month
	order by month
)
-- Основной запрос, в котором сведена информация о продажах и покупках:
select 
	sale_stat.month,              -- номер месяца
	sale_total_adv,               -- количество объявлений о продаже
	sale_avg_one_meter_price,     -- средняя цена одного квадратного метра в объявлении о продаже
	sale_avg_total_area,          -- средняя общая стоимость в объявлении о продаже
	sale_rank_month,              -- ранк месяца, в зависимости от количества объявлений о продаже 
	buy_total_adv,                -- количество объявлений, снятых с продажи 
	buy_avg_one_meter_price,      -- средняя цена одного квадратного метра в снятом объявлении о продаже
	buy_avg_total_area,           -- средняя общая площадь квартиры в снятом объявлении о продаже
	buy_rank_month                -- ранк месяца, в зависимости от количества снятых объявлений о продаже
from sale_stat
full join buy_stat on sale_stat.month = buy_stat.month;

-- Задача 3: Анализ рынка недвижимости Ленобласти
-- Результат запроса должен ответить на такие вопросы:
-- 1. В каких населённые пунктах Ленинградской области наиболее активно публикуют объявления о продаже недвижимости?
-- 2. В каких населённых пунктах Ленинградской области — самая высокая доля снятых с публикации объявлений? 
--    Это может указывать на высокую долю продажи недвижимости.
-- 3. Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир в различных населённых пунктах? 
--    Есть ли вариация значений по этим метрикам?
-- 4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? 
--    То есть где недвижимость продаётся быстрее, а где — медленнее.

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,           -- 99 процентиль по общей площади
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,                     -- 99 процентиль по количества комнат 
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,                 -- 99 процентиль по количеству балконов
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h, -- 99 процентиль по высоте потолков
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l  -- 1 процентиль по высоте потолков
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id                                        -- id квартир, после фильтрации 1 и 99 процентилем 
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Отфильтруем Ленинградскую область:
filtered_region as (
	SELECT 
		f.id,                                           -- id объявления
		a.last_price/f.total_area as one_meter_price,   -- цена одного квадратного метра 
		a.days_exposition,                              -- количество дней, когда объявление было в продаже
		f.total_area,                                   -- общая площадь квартиры
		f.rooms,                                        -- количество комнат 
		c.city,                                         -- название населенного пункта
		t.type                                          -- тип населенного пункта
	FROM real_estate.flats as f
	join real_estate.city as c on c.city_id = f.city_id
	join real_estate.type as t on t.type_id = f.type_id
	join real_estate.advertisement as a on a.id = f.id
	WHERE f.id IN (SELECT * FROM filtered_id)
		and c.city <> 'Санкт-Петербург'
)
-- Вывод статистики в основном запросе:
select
	city,                                                                                  -- название населенного пункта
	type,                                                                                  -- тип населенного пункта
	count(id) as total_adv,                                                                -- общее количество объявлений о продаже                                                      
	count(id) filter (where days_exposition is not null) as closed_adv,                    -- общее количество объявлений, снятых с продажи
	count(id) filter (where days_exposition is not null)*100/count(id) as perc_closed_adv, -- процент снятых с продажи объявлений
	round(avg(one_meter_price)::decimal,2) as avg_one_meter_price,                         -- средняя цена за квадратный метр
	round(avg(total_area::decimal),2) as avg_total_area,                                   -- средняя общая площадь недвижимости 
	round(avg(days_exposition)::decimal,2) as avg_days_exposition                          -- среднее количество дней, когда объявление было активно
from filtered_region
group by city, type
order by count(id) desc
limit 16;                                                                                  -- 16 записей для топ-15, так как Кудрово упоминается в выборке как деревня и как город