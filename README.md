# Cinema Database System

**Курсовая работа** по дисциплине "Базы данных" | КГЭУ, 2024

[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16+-blue)](https://www.postgresql.org/)

## О проекте
База данных для информационной поддержки сотрудников кинотеатров. Включает:
- учёт кинотеатров, залов и сеансов;
- управление фильмами и персонами (актёры, продюсеры);
- бронирование билетов с проверкой мест;
- разграничение прав доступа (админ, менеджер, зритель).

## Установка
1. Создать БД в PostgreSQL и подключиться к ней (psql/PGAdmin):
   ```
   CREATE DATABASE cinema_db;
   ```
2. Чтобы загрузить данные, нужно открыть PGAdmin, подключиться к серверу, затем скопировать содержимое файла code.sql и выполнить его в окне PGAdmin

## Типовые запросы к БД:
Список фильмов, которые были выпущены в определенном диапазоне лет, с дополнительной информацией о жанрах и актерах:
```
SELECT f.title AS film_title,
f.release_year,
f.rating,
ARRAY_AGG(g.genre) AS genres,
ARRAY_AGG(p.firstname || ' ' || p.secondname) AS actors
FROM films f
JOIN film_genre fg ON f.id = fg.film_id
JOIN genres g ON fg.genre_id = g.id
JOIN film_person fp ON f.id = fp.film_id
JOIN persons p ON fp.person_id = p.id
WHERE EXTRACT(YEAR FROM f.release_year) BETWEEN 2000 AND 2010
GROUP BY f.id
ORDER BY f.release_year DESC;
```
Средний рейтинг фильмов по годам выпуска:
```
SELECT f.release_year, AVG(f.rating) AS avg_rating
FROM films f
GROUP BY f.release_year
ORDER BY f.release_year DESC;
```

## Документация
Полная документация доступна в файле **Full Documentation.pdf**
