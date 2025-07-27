CREATE TABLE cinema_houses (
	id SERIAL PRIMARY KEY,
	name VARCHAR(128) NOT NULL,
	house_state STATES DEFAULT 'Работает',
	rating NUMERIC(4, 2) check (rating > 0 AND rating < 10),
	address VARCHAR(256) NOT NULL,
	phone_number VARCHAR(64) NOT NULL,
	number_halls INTEGER DEFAULT 0,
	capacity INTEGER DEFAULT 0,
	additional_services BOOLEAN DEFAULT false,
	start_work TIME NOT NULL,
	end_work TIME NOT NULL
);
CREATE TYPE STATES AS ENUM ('Работает', 'Ремонт', 'Закрыт');
CREATE TABLE cinema_halls (
	id SERIAL PRIMARY KEY,
	cinema_house_id INTEGER REFERENCES cinema_houses(id),
	name VARCHAR(64),
	hall_state STATES DEFAULT 'Работает',
	projector_type PROJECTOR DEFAULT 'Цифровой',
	screen_type INTEGER REFERENCES screen_types(id),
	videocamera BOOLEAN DEFAULT true,
	last_renovation_date DATE NOT NULL,
	seats_number INTEGER DEFAULT 0,
	rows_number INTEGER DEFAULT 0
);
CREATE TYPE PROJECTOR AS ENUM ('Цифровой', 'Лазерный', 'UHD', '4K', '3D');
CREATE TABLE screen_types (
	id SERIAL PRIMARY KEY,
	name VARCHAR(64) NOT NULL
);
CREATE TABLE additional_services (
	id SERIAL PRIMARY KEY,
	name VARCHAR(256) NOT NULL,
	description TEXT
);
CREATE TABLE addit_hall (
	hall_id INTEGER REFERENCES cinema_halls(id),
	service_id INTEGER REFERENCES additional_services(id),
	PRIMARY KEY (hall_id, service_id)
);
CREATE TABLE seats (
	hall_id INTEGER REFERENCES cinema_halls(id),
	row INTEGER CHECK (row > 0),
	seats INTEGER CHECK (seats > 0),
	PRIMARY KEY (hall_id, row)
);
CREATE TABLE films (
	id SERIAL PRIMARY KEY,
	title TEXT NOT NULL,
	description TEXT,
	release_year DATE NOT NULL,
	duration INTEGER CHECK (duration > 0),
	country VARCHAR(64) DEFAULT 'Россия',
	film_language VARCHAR(64) DEFAULT 'Русский',
	rating NUMERIC(4, 2) CHECK (rating > 0 AND rating < 10),
	format VARCHAR(16) CHECK (format in ('2D', '3D', 'IMAX')),
	price MONEY
);
CREATE TABLE persons (
	id SERIAL PRIMARY KEY,
	firstname TEXT NOT NULL,
	secondname TEXT NOT NULL,
	thirdname TEXT,
	birth_date DATE NOT NULL,
	age INTEGER,
	job VARCHAR(32) CHECK (job in ('Актёр', 'Продюсер')) DEFAULT 'Актёр',
	phone TEXT NOT NULL,
	email TEXT NOT NULL,
	experience INTEGER NOT NULL CHECK (experience > 0)
);
CREATE TABLE film_person (
	film_id INTEGER REFERENCES films(id),
	person_id INTEGER REFERENCES persons(id),
	PRIMARY KEY (film_id, person_id)
);
CREATE TABLE genres (
	id SERIAL PRIMARY KEY,
	description TEXT,
	genre TEXT NOT NULL
);
CREATE TABLE film_genre (
	film_id INTEGER REFERENCES films(id),
	genre_id INTEGER REFERENCES genres(id),
	PRIMARY KEY (film_id, genre_id)
);
CREATE TABLE film_screenings (
	id SERIAL PRIMARY KEY,
	film INTEGER REFERENCES films(id),
	hall INTEGER REFERENCES cinema_halls(id),
	start_time TIMESTAMP NOT NULL,
	end_tine TIMESTAMP NOT NULL,
	price MONEY,
	screening_state VARCHAR(32) CHECK (screening_state in
	('Доступен', 'Продан')) DEFAULT 'Доступен'
);
CREATE TABLE tickets (
	id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
	screening_id INTEGER REFERENCES film_screenings(id),
	row SMALLINT,
	seat SMALLINT,
	price MONEY
);
CREATE EXTENSION "uuid-ossp";


CREATE OR REPLACE FUNCTION update_number_halls() 
RETURNS TRIGGER AS $$
BEGIN
UPDATE cinema_houses
SET number_halls = (SELECT COUNT(*) FROM cinema_halls WHERE cinema_house_id = NEW.cinema_house_id)
WHERE id = NEW.cinema_house_id;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trigger_update_number_halls
AFTER INSERT ON cinema_halls
FOR EACH ROW
EXECUTE FUNCTION update_number_halls();

CREATE OR REPLACE FUNCTION update_capacity() 
RETURNS TRIGGER AS $$
BEGIN
UPDATE cinema_houses
SET capacity = (SELECT SUM(seats_number) FROM cinema_halls WHERE cinema_house_id = NEW.cinema_house_id)
WHERE id = NEW.cinema_house_id;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trigger_update_capacity
AFTER INSERT OR UPDATE ON cinema_halls
FOR EACH ROW
EXECUTE FUNCTION update_capacity();

CREATE OR REPLACE FUNCTION update_additional_services() 
RETURNS TRIGGER AS $$
BEGIN
	UPDATE cinema_houses
	SET additional_services = TRUE
	WHERE id = (
		SELECT cinema_house_id
		FROM cinema_halls
		WHERE id = NEW.hall_id
		LIMIT 1
	)
	AND EXISTS (
		SELECT 1
		FROM cinema_halls
		JOIN addit_hall ON cinema_halls.id = addit_hall.hall_id
		WHERE cinema_halls.cinema_house_id = (
			SELECT cinema_house_id
			FROM cinema_halls
			WHERE id = NEW.hall_id
			LIMIT 1
		)
	);
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trigger_update_additional_services
AFTER INSERT ON addit_hall
FOR EACH ROW
EXECUTE FUNCTION update_additional_services();

CREATE OR REPLACE FUNCTION update_hall_seat_count()
RETURNS TRIGGER AS $$
BEGIN
UPDATE cinema_halls
SET rows_number = (SELECT COUNT(DISTINCT row) FROM seats WHERE hall_id = NEW.hall_id) WHERE id = NEW.hall_id;
UPDATE cinema_halls
SET seats_number = (SELECT SUM(seats) FROM seats WHERE hall_id = NEW.hall_id) WHERE id = NEW.hall_id;
RETURN NEW;
END; 
$$ LANGUAGE plpgsql;
CREATE TRIGGER update_seat_count_after_insert
AFTER INSERT ON seats
FOR EACH ROW
EXECUTE FUNCTION update_hall_seat_count();

CREATE OR REPLACE FUNCTION calculate_age()
RETURNS TRIGGER AS $$
BEGIN
NEW.age := EXTRACT(YEAR FROM age(NEW.birth_date));
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER update_age_before_insert_or_update
BEFORE INSERT OR UPDATE ON persons
FOR EACH ROW
EXECUTE FUNCTION calculate_age();

CREATE FUNCTION check_overbooking() RETURNS TRIGGER AS $func$
DECLARE
    seat_possible BOOLEAN;
BEGIN
    SELECT true INTO seat_possible
    FROM seats 
    JOIN film_screenings ON film_screenings.hall = seats.hall_id 
    WHERE film_screenings.id = new.screening_id 
      AND seats.row = new.row 
      AND new.seat BETWEEN 1 AND seats.seats;
    IF (seat_possible IS NULL OR NOT seat_possible) THEN
        RAISE EXCEPTION 'The seat % in row % does not exist for screening %', new.seat, new.row, new.screening_id;
        RETURN NULL;
    END IF;
    IF EXISTS (
        SELECT 1
        FROM tickets
        WHERE screening_id = new.screening_id
          AND row = new.row
          AND seat = new.seat
    ) THEN
        RAISE EXCEPTION 'The seat % in row % is already booked for screening %', new.seat, new.row, new.screening_id;
        RETURN NULL;
    END IF;
    RETURN NEW;
END;
$func$ LANGUAGE plpgsql;
CREATE TRIGGER check_overbooking
BEFORE INSERT ON tickets
FOR EACH ROW
EXECUTE FUNCTION check_overbooking();

CREATE OR REPLACE FUNCTION calculate_screening_price()
RETURNS TRIGGER AS $$
BEGIN
	UPDATE film_screenings
	SET price = (SELECT price FROM films WHERE id = NEW.film) + 
              ((SELECT COUNT(*) * 10 FROM addit_hall WHERE hall_id = NEW.hall)::MONEY)
	WHERE id = NEW.id;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trigger_calculate_screening_price
AFTER INSERT ON film_screenings
FOR EACH ROW
EXECUTE FUNCTION calculate_screening_price();


CREATE OR REPLACE FUNCTION set_ticket_price() RETURNS TRIGGER AS $$
BEGIN
    SELECT price INTO NEW.price
    FROM film_screenings
    WHERE film_screenings.id = NEW.screening_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER set_ticket_price_trigger
BEFORE INSERT ON tickets
FOR EACH ROW
EXECUTE FUNCTION set_ticket_price();



INSERT INTO cinema_houses (name, rating, address, phone_number, start_work, end_work) VALUES
('Кинотеатр Люкс', 8.5, 'Казань, ул. Центральная, 12', '+7 123 456 7890', '10:00:00', '22:00:00'),
('СинемаПарк', 7.2, 'Казань, пр. Победы, 45', '+7 987 654 3210', '09:30:00', '23:00:00'),
('Кинотеатр Галактика', 9.1, 'Казань, ул. Мира, 101', '+7 555 123 4567', '11:00:00', '00:00:00'),
('Синемаград', 6.8, 'Казань, ул. Ленина, 34', '+7 800 123 9876', '10:30:00', '21:30:00'),
('Вестерн Кино', 8.2, 'Казань, пр. Советский, 56', '+7 123 987 6543', '12:00:00', '23:30:00');

INSERT INTO cinema_halls (cinema_house_id, name, hall_state, projector_type, screen_type, videocamera, last_renovation_date) VALUES
(1, 'Зал 1', 'Работает', 'Цифровой', 1, true, '2023-05-10'),
(2, 'Зал 1', 'Работает', 'Лазерный', 2, true, '2023-06-15'),
(2, 'Зал 2', 'Работает', 'UHD', 1, true, '2023-06-15'),
(3, 'Зал 1', 'Работает', '4K', 3, true, '2023-04-20'),
(3, 'Зал 2', 'Работает', 'Цифровой', 2, true, '2023-04-20'),
(3, 'Зал 3', 'Работает', 'Лазерный', 1, true, '2023-04-20'),
(4, 'Зал 1', 'Работает', 'UHD', 1, true, '2023-07-01'),
(4, 'Зал 2', 'Работает', 'Цифровой', 2, true, '2023-07-01'),
(4, 'Зал 3', 'Работает', '4K', 3, true, '2023-07-01'),
(4, 'Зал 4', 'Работает', '3D', 1, true, '2023-07-01'),
(5, 'Зал 1', 'Работает', 'Цифровой', 2, true, '2023-08-10'),
(5, 'Зал 2', 'Работает', 'Лазерный', 3, true, '2023-08-10');

INSERT INTO screen_types (name) VALUES
('IMAX'),
('2D'),
('3D'),
('4DX'),
('ScreenX');

INSERT INTO additional_services (name, description) VALUES
('Билеты с доставкой', 'Удобная доставка билетов на указанный адрес.'),
('VIP-зал', 'Специальный зал с улучшенными условиями просмотра.'),
('Попкорн и напитки', 'Заказ попкорна и напитков прямо в зал.'),
('Парковка', 'Обеспеченная парковка для зрителей.'),
('Детская комната', 'Комната для детей с присмотром во время сеанса.');

INSERT INTO seats (hall_id, row, seats) VALUES
(1, 1, 15),
(1, 2, 15),
(1, 3, 15),
(2, 1, 20),
(2, 2, 20),
(2, 3, 20),
(3, 1, 18),
(3, 2, 18),
(3, 3, 18),
(3, 4, 18),
(4, 1, 22),
(4, 2, 22),
(4, 3, 22),
(4, 4, 22),
(5, 1, 16),
(5, 2, 16),
(6, 1, 18),
(6, 2, 18),
(7, 1, 20),
(7, 2, 20),
(8, 1, 24),
(8, 2, 24),
(8, 3, 24),
(9, 1, 12),
(9, 2, 12),
(10, 1, 14),
(10, 2, 14),
(11, 1, 16),
(11, 2, 16),
(12, 1, 20),
(12, 2, 20);

INSERT INTO addit_hall (hall_id, service_id) VALUES
(1, 1),
(1, 2),
(1, 3),
(2, 1),
(2, 3),
(2, 4),
(3, 1),
(3, 3),
(4, 2),
(4, 4),
(5, 1),
(5, 5),
(6, 2),
(6, 3),
(7, 1),
(7, 4),
(8, 3),
(8, 5),
(9, 1),
(9, 2),
(10, 4),
(10, 3),
(11, 1),
(11, 5),
(12, 2),
(12, 4);

INSERT INTO genres (description, genre) VALUES
('Фильмы, которые исследуют человеческие эмоции и конфликты.', 'Драма'),
('Фильмы, основанные на научных и фантастических концепциях.', 'Фантастика'),
('Фильмы, которые вызывают смех и развлекают зрителей.', 'Комедия'),
('Фильмы, которые рассказывают истории о приключениях и действиях.', 'Экшен'),
('Фильмы, основанные на романтических отношениях между персонажами.', 'Романтика'),
('Фильмы, которые содержат элементы магии и волшебства.', 'Фэнтези'),
('Фильмы, основанные на реальных событиях или документальных фактах.', 'Документальный'),
('Анимационные фильмы, созданные с использованием различных техник анимации.', 'Анимация'),
('Фильмы ужасов, которые призваны напугать зрителей.', 'Ужасы'),
('Фильмы, которые исследуют социальные или политические темы.', 'Социальная драма'),
('Фильмы, в которых главными героями являются животные или природа.', 'Приключенческий'),
('Фильмы, которые используют элементы триллера для создания напряжения.', 'Триллер'),
('Фильмы, основанные на мифах и легендах.', 'Мифология'),
('Музыкальные фильмы, в которых музыка играет центральную роль.', 'Музыкальный'),
('Фильмы о детях и подростках, их проблемах и приключениях.', 'Подростковый'),
('Фильмы, которые исследуют темы самопознания и внутренней борьбы.', 'Психологический'),
('Исторические фильмы, которые рассказывают о событиях прошлого.', 'Исторический'),
('Фильмы о супергероях и их борьбе со злом.', 'Супергеройский'),
('Фильмы, которые фокусируются на спортивных событиях и соревнованиях.', 'Спортивный'),
('Фильмы, основанные на комиксах или графических новеллах.', 'Комикс');


INSERT INTO persons (firstname, secondname, thirdname, birth_date, job, phone, email, experience) VALUES
('Владимир', 'Сафонов', 'Владимирович', '1985-06-15', 'Актёр', '+79001234567', 'ivan.ivanov@example.com', 10),
('Мария', 'Петрова', 'Сергеевна', '1990-03-22', 'Продюсер', '+79007654321', 'maria.petrova@example.com', 5),
('Сергей', 'Сидоров', NULL, '1978-11-30', 'Актёр', '+79009876543', 'sergey.sidorov@example.com', 15),
('Анна', 'Кузнецова', 'Алексеевна', '1995-01-10', 'Актёр', '+79004561234', 'anna.kuznetsova@example.com', 3),
('Дмитрий', 'Смирнов', NULL, '1982-08-05', 'Продюсер', '+79005432123', 'dmitry.smirnov@example.com', 8),
('Елена', 'Фёдорова', 'Викторовна', '1989-02-14', 'Актёр', '+79006789012', 'elena.fedorova@example.com', 6),
('Александр', 'Николаев', NULL, '1975-04-20', 'Продюсер', '+79007890123', 'alexander.nikolaev@example.com', 12),
('Ольга', 'Морозова', 'Петровна', '1992-09-05', 'Актёр', '+79008901234', 'olga.morozova@example.com', 4),
('Владимир', 'Соловьёв', NULL, '1980-12-25', 'Актёр', '+79009123456', 'vladimir.soloviev@example.com', 7),
('Татьяна', 'Лебедева', 'Игоревна', '1988-07-30', 'Продюсер', '+79002345678', 'tatiana.lebedeva@example.com', 9),
('Максим', 'Григорьев', NULL, '1993-11-11', 'Актёр', '+79003456789', 'maxim.grigorev@example.com', 2),
('Ксения', 'Семенова', 'Анатольевна', '1991-05-18', 'Продюсер', '+79004567890', 'ksenia.semenova@example.com', 11);

INSERT INTO films (title, description, release_year, duration, country, film_language, rating, format, price) VALUES
('В поисках счастья', 'Драма о поисках смысла жизни.', '2006-01-01', 117, 'США', 'Английский', 8.0, '2D', 500.00),
('Зеленая миля', 'Фильм о тюремной жизни и чудесах.', '1999-12-10', 189, 'США', 'Английский', 9.2, '2D', 700.00),
('Интерстеллар', 'Научно-фантастический фильм о космосе.', '2014-11-07', 169, 'США', 'Английский', 8.6, 'IMAX', 800.00),
('Легенда №17', 'История хоккеиста Валерия Харламова.', '2013-01-01', 110, 'Россия', 'Русский', 7.5, '2D', 400.00),
('Титаник', 'Романтическая драма о трагедии Титаника.', '1997-12-19', 195, 'США', 'Английский', 7.8, '3D', 600.00),
('Время первых', 'Фильм о космонавтах и их подвиге.', '2017-04-20', 140, 'Россия', 'Русский', 8.1, '2D', 450.00),
('Сталкер', 'Фантастическая драма о Зоне.', '1979-04-14', 163, 'СССР', 'Русский', 8.3, '2D', 300.00),
('Властелин колец: Братство кольца', 'Фэнтези о борьбе за кольцо.', '2001-12-19', 178, 'Новая Зеландия', 'Английский', 8.8, 'IMAX', 900.00),
('Матрица', 'Научно-фантастический фильм о виртуальной реальности.', '1999-03-31', 136, 'США', 'Английский', 8.7, '2D', 500.00),
('Пираты Карибского моря: Проклятие черной жемчужины', 'Приключения пиратов в Карибском море.', '2003-07-09', 143, 'США', 'Английский', 8.0, '2D', 550.00),
('Гарри Поттер и философский камень', 'Фильм о приключениях молодого волшебника.', '2001-11-16', 152, 'Великобритания', 'Английский', 7.9, '2D', 650.00),
('Достучаться до небес', 'Комедия о двух друзьях с необычной мечтой.', '1997-04-17', 103, 'Германия', 'Немецкий', 8.5, '2D', 350.00),
('Крепкий орешек', 'Боевик о полицейском в небоскребе.', '1988-07-20', 132, 'США', 'Английский', 8.2, '2D', 400.00),
('Шерлок Холмс: Игра теней', 'Приключения знаменитого детектива.', '2011-12-16', 129, 'США/Великобритания', 'Английский', 7.5, '2D', 500.00),
('Джуманджи: Зов джунглей', 'Приключенческий фильм о волшебной игре.', '2017-12-20', 119, 'США', 'Английский', 6.9, '3D', 450.00),
('Книга джунглей', 'Приключения Маугли в джунглях.', '2016-04-15', 106, 'США', 'Английский', 7.4, '3D', 500.00),
('Однажды в Голливуде', 'Фильм о золотой эпохе Голливуда.', '2019-07-26', 161, 'США', 'Английский', 7.6, '2D', 600.00),
('Мстители: Финал', 'Эпическая битва супергероев.', '2019-04-26', 181, 'США', 'Английский', 8.4, 'IMAX', 850.00),
('Тайна третьей планеты', 'Анимационный фильм о приключениях в космосе.', '1981-12-31', 75, 'СССР', 'Русский', 8.0, '2D', 200.00),
('Небо над Берлином', 'Поэтичная история о ангелах и людях.', '1987-02-18', 128, 'Германия/Франция', 'Немецкий/Французский', 8.3, '2D', 300.00);


INSERT INTO film_genre (film_id, genre_id) VALUES
(1, (SELECT id FROM genres WHERE genre = 'Драма')),
(1, (SELECT id FROM genres WHERE genre = 'Социальная драма')),
(2, (SELECT id FROM genres WHERE genre = 'Драма')),
(2, (SELECT id FROM genres WHERE genre = 'Социальная драма')),
(3, (SELECT id FROM genres WHERE genre = 'Фантастика')),
(3, (SELECT id FROM genres WHERE genre = 'Драма')),
(4, (SELECT id FROM genres WHERE genre = 'Драма')),
(4, (SELECT id FROM genres WHERE genre = 'Спортивный')),
(5, (SELECT id FROM genres WHERE genre = 'Романтика')),
(5, (SELECT id FROM genres WHERE genre = 'Драма')),
(6, (SELECT id FROM genres WHERE genre = 'Драма')),
(6, (SELECT id FROM genres WHERE genre = 'Исторический')),
(7, (SELECT id FROM genres WHERE genre = 'Фантастика')),
(7, (SELECT id FROM genres WHERE genre = 'Драма')),
(8, (SELECT id FROM genres WHERE genre = 'Фэнтези')),
(8, (SELECT id FROM genres WHERE genre = 'Приключенческий')),
(9, (SELECT id FROM genres WHERE genre = 'Фантастика')),
(9, (SELECT id FROM genres WHERE genre = 'Экшен')),
(10, (SELECT id FROM genres WHERE genre = 'Приключенческий')),
(10, (SELECT id FROM genres WHERE genre = 'Экшен')),
(11, (SELECT id FROM genres WHERE genre = 'Фэнтези')),
(11, (SELECT id FROM genres WHERE genre = 'Приключенческий')),
(12, (SELECT id FROM genres WHERE genre = 'Комедия')),
(13, (SELECT id FROM genres WHERE genre = 'Экшен')),
(14, (SELECT id FROM genres WHERE genre = 'Экшен')),
(15, (SELECT id FROM genres WHERE genre = 'Приключенческий')),
(15, (SELECT id FROM genres WHERE genre = 'Комедия')),
(16, (SELECT id FROM genres WHERE genre = 'Приключенческий')),
(17, (SELECT id FROM genres WHERE genre = 'Драма')),
(18, (SELECT id FROM genres WHERE genre = 'Экшен')),
(19, (SELECT id FROM genres WHERE genre = 'Фантастика')),
(20, (SELECT id FROM genres WHERE genre = 'Драма'));

INSERT INTO film_person (film_id, person_id) VALUES
(1, 3),
(1, 4),
(1, 5),
(1, 6),
(2, 3),
(2, 6),
(2, 7),
(3, 4),
(3, 10),
(3, 8),
(4, 5),
(4, 11),
(4, 12),
(5, 6),
(5, 9),
(5, 7),
(6, 3),
(6, 8),
(6, 4),
(7, 4),
(7, 8),
(7, 7),
(8, 10),
(8, 11),
(8, 8),
(9, 4),
(9, 9),
(9, 12),
(10, 5),
(10, 8),
(10, 7),
(11, 3),
(11, 4),
(11, 5),
(12, 11),
(12, 6),
(12, 8),
(13, 9),
(13, 8),
(13, 10),
(14, 4),
(14, 3),
(14, 7),
(15, 11),
(15, 9),
(15, 12),
(16, 5),
(16, 3),
(16, 8),
(17, 6),
(17, 8),
(17, 7),
(18, 9),
(18, 4),
(18, 12),
(19, 10),
(19, 11),
(19, 8),
(20, 8),
(20, 9),
(20, 7);


INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(1, 1, '2024-12-22 10:00:00', '2024-12-22 12:00:00', 'Доступен'),
(2, 2, '2024-12-22 14:00:00', '2024-12-22 16:00:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(3, 3, '2024-12-23 10:00:00', '2024-12-23 12:30:00', 'Доступен'),
(4, 4, '2024-12-23 14:00:00', '2024-12-23 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(5, 5, '2024-12-24 10:00:00', '2024-12-24 12:30:00', 'Доступен'),
(6, 6, '2024-12-24 14:00:00', '2024-12-24 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(7, 7, '2024-12-25 10:00:00', '2024-12-25 12:30:00', 'Доступен'),
(8, 8, '2024-12-25 14:00:00', '2024-12-25 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(9, 9, '2024-12-26 10:00:00', '2024-12-26 12:00:00', 'Доступен'),
(10, 10, '2024-12-26 14:00:00', '2024-12-26 16:00:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(11, 11, '2024-12-27 10:00:00', '2024-12-27 12:00:00', 'Доступен'),
(12, 12, '2024-12-27 14:00:00', '2024-12-27 16:00:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(13, 1, '2024-12-28 10:00:00', '2024-12-28 12:00:00', 'Доступен'),
(14, 2, '2024-12-28 14:00:00', '2024-12-28 16:00:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(15, 3, '2024-12-29 10:00:00', '2024-12-29 12:00:00', 'Доступен'),
(16, 4, '2024-12-29 14:00:00', '2024-12-29 16:00:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(17, 5, '2024-12-30 10:00:00', '2024-12-30 12:00:00', 'Доступен'),
(18, 6, '2024-12-30 14:00:00', '2024-12-30 16:00:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(19, 7, '2024-12-31 10:00:00', '2024-12-31 12:00:00', 'Доступен'),
(20, 8, '2024-12-31 14:00:00', '2024-12-31 16:00:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(1, 9, '2025-01-01 10:00:00', '2025-01-01 12:00:00', 'Доступен'),
(2, 10, '2025-01-01 14:00:00', '2025-01-01 16:00:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(3, 11, '2025-01-02 10:00:00', '2025-01-02 12:30:00', 'Доступен'),
(4, 12, '2025-01-02 14:00:00', '2025-01-02 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(5, 1, '2025-01-03 10:00:00', '2025-01-03 12:30:00', 'Доступен'),
(6, 2, '2025-01-03 14:00:00', '2025-01-03 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(7, 3, '2025-01-04 10:00:00', '2025-01-04 12:30:00', 'Доступен'),
(8, 4, '2025-01-04 14:00:00', '2025-01-04 16:30:00', 'Доступен');

INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(19, 5, '2025-01-05 10:00:00', '2025-01-05 12:30:00', 'Доступен'),
(3, 6, '2025-01-05 14:00:00', '2025-01-05 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(5, 7, '2025-01-06 10:00:00', '2025-01-06 12:30:00', 'Доступен'),
(6, 8, '2025-01-06 14:00:00', '2025-01-06 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(20, 9, '2025-01-07 10:00:00', '2025-01-07 12:30:00', 'Доступен'),
(20, 9, '2025-01-07 14:00:00', '2025-01-07 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(18, 10, '2025-01-08 10:00:00', '2025-01-08 12:30:00', 'Доступен'),
(16, 10, '2025-01-08 14:00:00', '2025-01-08 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(15, 1, '2025-01-09 10:00:00', '2025-01-09 12:30:00', 'Доступен'),
(15, 6, '2025-01-09 14:00:00', '2025-01-09 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(13, 7, '2025-01-10 10:00:00', '2025-01-10 12:30:00', 'Доступен'),
(13, 8, '2025-01-10 14:00:00', '2025-01-10 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(12, 9, '2025-01-11 10:00:00', '2025-01-11 12:30:00', 'Доступен'),
(12, 10, '2025-01-11 10:00:00', '2025-01-11 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(1, 11, '2025-01-12 10:00:00', '2025-01-12 12:30:00', 'Доступен'),
(2, 12, '2025-01-12 14:00:00', '2025-01-12 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(1, 1, '2025-01-13 10:00:00', '2025-01-13 12:30:00', 'Доступен'),
(1, 2, '2025-01-13 14:00:00', '2025-01-13 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(5, 3, '2025-01-14 10:00:00', '2025-01-14 12:30:00', 'Доступен'),
(5, 4, '2025-01-14 14:00:00', '2025-01-14 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(6, 5, '2025-01-15 10:00:00', '2025-01-15 12:30:00', 'Доступен'),
(19, 6, '2025-01-15 14:00:00', '2025-01-15 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(16, 7, '2025-01-16 10:00:00', '2025-01-16 12:30:00', 'Доступен'),
(15, 8, '2025-01-16 14:00:00', '2025-01-16 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(16, 9, '2025-01-17 10:00:00', '2025-01-17 12:30:00', 'Доступен'),
(18, 10, '2025-01-17 14:00:00', '2025-01-17 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(2, 11, '2025-01-18 10:00:00', '2025-01-18 12:30:00', 'Доступен'),
(5, 12, '2025-01-18 14:00:00', '2025-01-18 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(9, 1, '2025-01-19 10:00:00', '2025-01-19 12:30:00', 'Доступен'),
(7, 2, '2025-01-19 14:00:00', '2025-01-19 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(1, 3, '2025-01-20 10:00:00', '2025-01-20 12:30:00', 'Доступен'),
(15, 4, '2025-01-20 14:00:00', '2025-01-20 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(19, 5, '2025-01-21 10:00:00', '2025-01-21 12:30:00', 'Доступен'),
(20, 6, '2025-01-21 14:00:00', '2025-01-21 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(17, 7, '2025-01-22 10:00:00', '2025-01-22 12:30:00', 'Доступен'),
(1, 8, '2025-01-22 14:00:00', '2025-01-22 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(18, 9, '2025-01-23 10:00:00', '2025-01-23 12:30:00', 'Доступен'),
(19, 10, '2025-01-23 14:00:00', '2025-01-23 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(3, 11, '2025-01-24 10:00:00', '2025-01-24 12:30:00', 'Доступен'),
(10, 12, '2025-01-24 14:00:00', '2025-01-24 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(7, 1, '2025-01-25 10:00:00', '2025-01-25 12:30:00', 'Доступен'),
(17, 2, '2025-01-25 14:00:00', '2025-01-25 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(8, 3, '2025-01-26 10:00:00', '2025-01-26 12:30:00', 'Доступен'),
(18, 4, '2025-01-26 14:00:00', '2025-01-26 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(6, 5, '2025-01-27 10:00:00', '2025-01-27 12:30:00', 'Доступен'),
(16, 6, '2025-01-27 14:00:00', '2025-01-27 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(10, 7, '2025-01-28 10:00:00', '2025-01-28 12:30:00', 'Доступен'),
(11, 8, '2025-01-28 14:00:00', '2025-01-28 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(9, 9, '2025-01-29 10:00:00', '2025-01-29 12:30:00', 'Доступен'),
(19, 10, '2025-01-29 14:00:00', '2025-01-29 16:30:00', 'Доступен');
INSERT INTO film_screenings (film, hall, start_time, end_tine, screening_state) VALUES
(10, 11, '2025-01-30 10:00:00', '2025-01-30 12:30:00', 'Доступен'),
(20, 12, '2025-01-30 14:00:00', '2025-01-30 16:30:00', 'Доступен');


INSERT INTO tickets (screening_id, row, seat) VALUES
(1, 1, 11),
(2, 2, 2),
(3, 1, 2),
(5, 1, 3),
(6, 1, 4),
(7, 1, 5),
(8, 1, 6),
(9, 1, 7),
(10, 1, 8),
(11, 1, 9),
(12, 1, 10),
(13, 2, 1),
(14, 2, 2),
(15, 2, 3),
(16, 2, 4);



CREATE INDEX idx_film_screenings_start_time ON film_screenings(start_time);
CREATE INDEX idx_films_title ON films(title);
CREATE INDEX idx_tickets_screening_row_seat ON tickets(screening_id, row, seat);


CREATE ROLE admin LOGIN PASSWORD 'admin';
CREATE ROLE manager LOGIN PASSWORD 'manager';
CREATE ROLE visitor LOGIN PASSWORD 'visitor';
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO admin;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO manager;
GRANT USAGE, SELECT ON SEQUENCE additional_services_id_seq TO manager;
GRANT SELECT ON films TO visitor;
GRANT SELECT ON cinema_houses TO visitor;
GRANT SELECT ON cinema_halls TO visitor;
GRANT SELECT ON film_screenings TO visitor;
GRANT SELECT ON tickets TO visitor;
GRANT SELECT ON seats TO visitor;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE ON TABLES TO manager;


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


SELECT ch.name AS cinema_house_name,
	f.title AS film_title,
	COUNT(fs.id) AS num_screenings
FROM cinema_houses ch
JOIN cinema_halls chh ON ch.id = chh.cinema_house_id
JOIN film_screenings fs ON chh.id = fs.hall
JOIN films f ON fs.film = f.id
GROUP BY ch.name, f.title
ORDER BY num_screenings DESC
LIMIT 3;

SELECT fs.start_time,
	f.title AS film_title,
	f.price AS film_price,
	ch.name AS cinema_hall_name
FROM film_screenings fs
JOIN films f ON fs.film = f.id
JOIN cinema_halls ch ON fs.hall = ch.id
WHERE fs.start_time BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'
ORDER BY fs.start_time;


SELECT f.title AS film_title,
	g.genre AS film_genre,
	ch.name AS cinema_hall_name,
	AVG(t.price::NUMERIC) AS avg_ticket_price
FROM films f
JOIN film_genre fg ON f.id = fg.film_id
JOIN genres g ON fg.genre_id = g.id
JOIN film_screenings fs ON f.id = fs.film
JOIN cinema_halls ch ON fs.hall = ch.id
JOIN tickets t ON fs.id = t.screening_id
GROUP BY f.id, g.genre, ch.id
ORDER BY avg_ticket_price DESC;


SELECT f.title
FROM films f
WHERE NOT EXISTS (
	SELECT 1
	FROM film_screenings fs
	WHERE fs.film = f.id
		AND fs.start_time BETWEEN DATE_TRUNC('MONTH', CURRENT_DATE + INTERVAL '1 month') AND DATE_TRUNC('MONTH', CURRENT_DATE + INTERVAL '2 month')
)
ORDER BY f.title;


SELECT f.title AS film_title, ch.name AS cinema_hall_name, COUNT(t.id) AS tickets_sold
FROM tickets t
JOIN film_screenings fs ON t.screening_id = fs.id
JOIN films f ON fs.film = f.id
JOIN cinema_halls ch ON fs.hall = ch.id
GROUP BY f.title, ch.name
ORDER BY tickets_sold DESC;

SELECT f.release_year, AVG(f.rating) AS avg_rating
FROM films f
GROUP BY f.release_year
ORDER BY f.release_year DESC;

SELECT f.title AS film_title, COUNT(fs.id) AS num_screenings
FROM films f
JOIN film_genre fg ON f.id = fg.film_id
JOIN genres g ON fg.genre_id = g.id
JOIN film_screenings fs ON f.id = fs.film
GROUP BY f.id
HAVING COUNT(DISTINCT g.id) > 1
ORDER BY num_screenings DESC;


SELECT fs.start_time, f.title AS film_title, ch.name AS cinema_hall_name
FROM film_screenings fs
JOIN films f ON fs.film = f.id
JOIN cinema_halls ch ON fs.hall = ch.id
JOIN cinema_houses chh ON ch.cinema_house_id = chh.id
WHERE fs.start_time::TIME BETWEEN chh.start_work AND chh.end_work
ORDER BY fs.start_time;


SELECT DISTINCT f.title AS film_title, ch.name AS cinema_hall_name, asv.name AS service_name
FROM films f
JOIN film_screenings fs ON f.id = fs.film
JOIN cinema_halls ch ON fs.hall = ch.id
JOIN addit_hall ah ON ch.id = ah.hall_id
JOIN additional_services asv ON ah.service_id = asv.id
WHERE asv.name IN ('Билеты с доставкой', 'VIP-зал')
ORDER BY f.title;





CREATE VIEW repertoire_next_30_days AS
SELECT fs.start_time,
	fs.end_tine,
	f.title AS film_title,
	f.price AS ticket_price,
	ch.name AS cinema_hall_name,
	chh.name AS cinema_house_name
FROM film_screenings fs
JOIN films f ON fs.film = f.id
JOIN cinema_halls ch ON fs.hall = ch.id
JOIN cinema_houses chh ON ch.cinema_house_id = chh.id
WHERE fs.start_time BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'
ORDER BY fs.start_time;

CREATE VIEW high_rated_films AS
SELECT f.title, f.release_year, f.rating, f.price
FROM films f
WHERE f.rating > 8
ORDER BY f.rating DESC;
