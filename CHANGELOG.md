# Cambios · Changelog

## 1.3.0 · 2026-11

**PvE**
- **New: PvE > Records and PvE > History.** Records shows a podium for each dungeon. History shows every guild run as a card with its members, bosses, time, deaths (or "no deaths"), gold looted and the best loot (hover for the item).
- **Official attempts:** only official runs count for guild records. An official run is a full guild group (5/5, or the whole raid), declared before the first kill, with every member paying 15 badges. The time starts at the first kill, not at the entrance, and leaving and coming back is still the same run. During an official attempt you see your pace against the record at each boss, and a new record is announced to the guild.
- **Guild group = more than half the group from the guild** (3/5, 6/10, 13/25, 21/40) for achievements, legacy challenges and medals. Badges per dungeon still need 4 or 5. The history shows runs with 3 or more from the guild; outsiders appear in grey.
- **New dungeons recognised:** the final boss of Forever's new dungeons is learned from your own runs.
- **Four new guild achievements:** Flawless (a dungeon with nobody dying), Untouchables (10 of them), Legendary Loot (an epic drop) and Treasure Hunters (100 gold looted across guild dungeons).
- Dungeon cards use the game's own loading-screen art.

**PvP**
- **PvP > Targets redesigned:** rank enemy guilds by *Who we hunt most* or *Who kills us most* over 7 days, 30 days or all time. Each card shows a kills/deaths bar, our best hunter and their most dangerous player, plus the enemy guild's tabard, shared across the guild once anyone has seen it.
- **One death, one kill:** when several members get honor for the same kill, guild totals (achievements, faction season, activity, tribes) count it once. Personal rankings still give everyone their kill.
- **Fixed: death warnings sometimes showed twice.** The game can report one death twice, and the addon saved it twice. Copies are now ignored when they arrive from members on older versions, and copies already saved stop counting.
- The first faction season starts on Forever's launch day for everyone, so every addon announces the same totals.

**Sync**
- Every 20 minutes, online members compare a summary of the last three weeks of kills and dungeons and fill in each other's gaps, so what one member missed is no longer lost until someone logs in.
- Guild chat posts and network announcements wait until the addon has synced, so an alt or a fresh install no longer posts things the guild already had, or posts in guilds that turned announcements off.
- Faction hunter lists keep the most complete version received (for 2 hours), so an older addon no longer replaces them with an empty list.

**Performance**
- **Fewer stutters:** working out achievements and the portrait badges now happens in small chunks in the background (a few milliseconds per frame) instead of freezing the game for 20–60 ms. Dungeon runs, duplicate kills and kill streaks are cached, and points were recalculated about twice as fast in testing.
- Asking the game for the guild roster is limited to once every 15 seconds.
- **"You're doing that too fast":** if this red game message appears, the addon now prints which addon (or the game) made the rate-limited calls just before it, so the right culprit can be reported.

**Interface**
- New round emblem for the minimap button and the window portrait; the guild name and its title sit on separate lines in the header.
- The window close button works in combat, and while the window is open only Escape is captured: every other key still reaches the game.

---

**JcE**
- **Nuevo: JcE > Récords y JcE > Historial.** Récords muestra un podio de cada mazmorra. Historial muestra cada partida de la hermandad como una tarjeta con sus miembros, jefes, tiempo, muertes (o «sin muertes»), oro conseguido y el mejor botín (pasa el ratón para ver el objeto).
- **Intentos oficiales:** solo las partidas oficiales cuentan para los récords de la hermandad. Una partida oficial es un grupo entero de la hermandad (5/5, o la banda entera), declarada antes de la primera baja, en la que cada miembro paga 15 insignias. El tiempo empieza con la primera baja, no en la entrada, y salir y volver sigue siendo la misma partida. Durante un intento oficial ves tu ritmo frente al récord en cada jefe, y un récord nuevo se anuncia a la hermandad.
- **Grupo de hermandad = más de la mitad del grupo de la hermandad** (3/5, 6/10, 13/25, 21/40) para logros, desafíos de legado y medallas. Las insignias por mazmorra siguen pidiendo 4 o 5. El historial muestra las partidas con 3 o más de la hermandad; los de fuera salen en gris.
- **Mazmorras nuevas reconocidas:** el jefe final de las mazmorras nuevas de Forever se aprende de vuestras propias partidas.
- **Cuatro logros de hermandad nuevos:** Impecable (una mazmorra sin que caiga nadie), Intocables (10), Botín de leyenda (que caiga un épico) y Cazatesoros (100 de oro entre todas las mazmorras de hermandad).
- Las tarjetas de mazmorra usan el arte de las pantallas de carga del juego.

**JcJ**
- **JcJ > Objetivos renovado:** ordena las hermandades enemigas por *A quién más cazamos* o *Quién más nos mata* en 7 días, 30 días o el total. Cada tarjeta muestra una barra de bajas/muertes, nuestro mejor cazador y su jugador más peligroso, y el estandarte de la hermandad enemiga, que se comparte con toda la hermandad en cuanto alguien lo ve.
- **Una muerte, una baja:** cuando varios del grupo reciben honor por la misma baja, los totales de la hermandad (logros, temporada de facción, actividad, tribus) la cuentan una vez. En los rankings personales cada uno sigue teniendo la suya.
- **Arreglado: los avisos de muerte salían a veces dobles.** El juego puede avisar dos veces de una misma muerte y el addon la guardaba dos veces. Ahora se ignoran las copias que llegan de compañeros con versiones anteriores, y las que ya estaban guardadas dejan de contar.
- La primera temporada de facción empieza para todos el día del lanzamiento de Forever, así que todos los addons anuncian los mismos totales.

**Sincronización**
- Cada 20 minutos, los conectados comparan un resumen de las bajas y mazmorras de las últimas tres semanas y se completan los huecos entre ellos, así que lo que se perdió uno ya no espera a que alguien vuelva a entrar.
- Los mensajes en el chat de hermandad y los anuncios de la red esperan a que el addon se haya sincronizado: un alter o una instalación nueva ya no anuncia lo que la hermandad ya tenía, ni escribe en hermandades que han quitado los anuncios.
- Las listas de cazadores de la facción se quedan con la versión más completa que llega (durante 2 horas): un addon antiguo ya no las sustituye por una lista vacía.

**Rendimiento**
- **Menos tirones:** el cálculo de los logros y de las insignias del retrato se hace ahora a trozos pequeños en segundo plano (unos milisegundos por frame) en vez de congelar el juego 20–60 ms de golpe. Las partidas de mazmorra, las bajas repetidas y las rachas se guardan en caché, y en las pruebas los puntos se recalculan casi el doble de rápido.
- La petición de la lista de la hermandad al juego se limita a una cada 15 segundos.
- **«Lo estás haciendo demasiado rápido»:** si sale este mensaje rojo del juego, el addon dice ahora qué addon (o el propio juego) hizo justo antes las llamadas con límite, para poder avisar al culpable.

**Interfaz**
- Emblema redondo nuevo en el botón del minimapa y en el retrato de la ventana; el nombre de la hermandad y su título van en líneas separadas en la cabecera.
- El botón de cerrar la ventana funciona en combate, y con la ventana abierta solo se captura Escape: las demás teclas siguen llegando al juego.

## 1.2.0 · 2026-11

- **PvP kills stay in sync between online members:** if the live message about a kill got lost (the game drops messages when there is a lot of traffic), members who were online never got it until they logged in again. Now each player regularly sends a tiny summary of how many of their own kills and deaths they have from today and yesterday, and anyone missing some asks them for the rest.
- **New: PvP > Hunters.** Its own tab for the guild hunters: kill streaks happening right now, a podium (last 7 or 30 days) with kills, deaths, K/D, revenges, honor and favourite victim, the rest of the ranking, and streak records.
- **Kill streaks:** honorable kills in a row without dying to another player (battlegrounds don't count). Three new guild achievements: Unstoppable (5), No Mercy (10) and Legend of the Frontier (20).
- **Participation ranking (PvP > Hunters):** switch between killing blows and participation. Participation uses the game's world honorable kills statistic (no battlegrounds), which counts everyone who helps with a kill, so healers and tanks rank fairly. All-time totals straight away, plus the last 7 or 30 days (counted from when you install 1.2.0).
- **New: Faction > Hunters.** The same for your whole faction: streaks happening right now, the top 15 by killing blows or participation (7 days, 30 days or all time) and the streak records, with each player's guild. Every guild shares its top 5 of each list on the guild network.
- **New: PvP > Log.** The latest kills and deaths now have their own section (up to 60), with a filter for all, kills or deaths. Targets is lighter.
- **Fixed: missing icons.** The Decorated, Hall of Heroes and Chest of Medals achievements, the Feats of Strength category, war league trophies and the guild level-up banner used trophy icons that don't exist in Forever; they now have their own.

---

- **Las muertes de JcJ se mantienen iguales entre los conectados:** si se perdía el aviso en directo de una muerte (el juego descarta mensajes cuando hay mucho tráfico), los que estaban conectados no la recibían hasta volver a entrar. Ahora cada jugador manda de vez en cuando un resumen pequeñito de cuántas bajas y muertes suyas tiene de hoy y de ayer, y a quien le falte alguna se la pide.
- **Nuevo: JcJ > Cazadores.** Pestaña propia para los cazadores de la hermandad: rachas en curso, podio (últimos 7 o 30 días) con bajas, muertes, K/D, venganzas, honor y víctima favorita, el resto de la clasificación y los récords de racha.
- **Rachas de bajas:** bajas con honor seguidas sin caer ante otro jugador (los campos de batalla no cuentan). Tres logros de hermandad nuevos: Imparable (5), Sin piedad (10) y Leyenda de la frontera (20).
- **Clasificación por participación (JcJ > Cazadores):** botón para cambiar entre golpes de gracia y participación. La participación usa la estadística del juego de muertes con honor en el mundo (sin campos de batalla), que cuenta a todos los que ayudan en la baja: sanadores y tanques salen como merecen. El total de siempre desde el primer momento, y los últimos 7 o 30 días (contando desde que instalas la 1.2.0).
- **Nuevo: Facción > Cazadores.** Lo mismo para toda tu facción: rachas en curso, los 15 mejores por golpes de gracia o participación (7 días, 30 días o total) y los récords de racha, con la hermandad de cada uno. Cada hermandad comparte sus 5 mejores de cada lista en la red de hermandades.
- **Nuevo: JcJ > Registro.** Las últimas kills y muertes tienen su propio apartado (hasta 60), con filtro de todo, cazas o caídos. Objetivos queda más ligero.
- **Arreglado: iconos que no se veían.** Los logros Condecorados, Galería de héroes y Pecho de medallas, la categoría Proezas de fuerza, los trofeos de liga de las guerras y el cartel de subida de nivel usaban iconos de trofeo que no existen en Forever; ahora tienen los suyos.

## 1.1.5 · 2026-11

- **Fixed: guild achievement banner only showed for one member.** It appeared only on the addon that noticed the achievement first; everyone else just received it silently. Now every online member sees the banner (only for achievements earned in the last 10 minutes).
- **New settings (Settings > Warnings):** turn off guild achievement banners on screen (personal), and stop the addon posting guild achievements in guild chat (guild setting, changed by officers).
- **Faction records only count guild groups:** the season's best dungeon times now only count runs done with a guild group (4 or 5 from the guild), the same rule as completed dungeons. Before, a time with a group of strangers could show up as the guild's record.

---

- **Arreglado: el cartel de logro de hermandad solo le salía a uno.** Aparecía únicamente en el addon que se daba cuenta primero; a los demás les llegaba sin aviso. Ahora lo ven todos los conectados (solo para logros conseguidos en los últimos 10 minutos).
- **Ajustes nuevos (Ajustes > Avisos):** quitar los carteles de logro de hermandad en pantalla (personal) y que el addon no escriba los logros de hermandad en el chat de hermandad (ajuste de hermandad, lo cambian los oficiales).
- **Los récords de facción solo cuentan grupos de hermandad:** los mejores tiempos de mazmorra de la temporada solo cuentan las partidas hechas con grupo de hermandad (4 o 5 de la guild), la misma regla que las mazmorras completadas. Antes, un tiempo con un grupo de desconocidos podía salir como récord de la hermandad.

## 1.1.4 · 2026-11

- **Fewer stutters:** every guild message (activity, guilds seen, member records...) recalculated the whole guild's points on the spot, even when it didn't affect them. Points are now only recalculated when something that counts for them changes, and refreshes are grouped (at most once per second, once every 3 seconds in combat). Working out kills on target guilds also went through the whole history for every kill; it now does a single pass and is far faster.
- **New: `/gmk performance`** shows which parts of the addon take the most time and how many stutters they caused, so slowdowns can be reported.

---

- **Menos tirones:** cada mensaje de la hermandad (actividad, hermandades vistas, fichas...) recalculaba al momento los puntos de toda la hermandad, aunque no les afectara. Ahora los puntos solo se recalculan cuando cambia algo que cuenta para ellos, y los refrescos se agrupan (como mucho uno por segundo, uno cada 3 segundos en combate). Además, el cálculo de las bajas a hermandades objetivo repasaba todo el historial por cada baja; ahora lo recorre una sola vez y tarda muchísimo menos.
- **Nuevo: `/gmk rendimiento`** muestra qué partes del addon gastan más tiempo y cuántos tirones han causado, para poder avisar si algo va lento.

## 1.1.3 · 2026-11

- **Arreglado: error «script ran too long» al sincronizar.** En hermandades grandes, contestar a quien acababa de entrar obligaba a comprimir todo el estado de la hermandad de golpe, se pasaba del tiempo que deja el juego y quien entraba se quedaba sin sincronizar. Ahora sale en varios mensajes más pequeños.
- **Arreglado: logros repetidos en el chat.** Quien entraba sin tener aún toda la sincronización podía anunciar como nuevo un logro que la hermandad ya tenía. Ahora se espera a recibirla entera y, si aun así alguien lo da por nuevo, los que ya lo tenían le avisan antes de que salga en el chat.
- **Arreglado: la colecta del banco no le llegaba a quien instalaba el addon.** Ahora el tesorero (o el maestro de hermandad, si el tesorero no está) le pasa la colecta y las aportaciones a quien entra sin tenerlas.

---

- **Fixed: "script ran too long" error when syncing.** In big guilds, answering a guildmate who just logged in meant compressing the whole guild state at once, which ran past the game's time limit and left them unsynced. It now goes out in several smaller messages.
- **Fixed: repeated achievements in chat.** Someone logging in before receiving the full sync could announce an achievement the guild already had as new. The addon now waits for the whole sync and, if someone still reports it as new, those who already had it tell them before it reaches the chat.
- **Fixed: the bank fundraiser didn't reach people who just installed the addon.** The treasurer (or the guild master, if the treasurer is offline) now sends the fundraiser and its donations to anyone who logs in without them.

## 1.1.2 · 2026-11

- **Arreglado: cada uno veía bajas distintas** (por ejemplo en «Cazadores de la semana»). Si te perdías unas bajas de un compañero y luego veías en directo otra suya más reciente, las anteriores ya no te llegaban nunca. Ahora, al entrar, el addon compara cuántas bajas y mazmorras tiene de cada compañero y día de las últimas tres semanas y pide los días que no cuadran. Además, quien entra le devuelve a quien le contesta lo que a este le faltaba, así que cada entrada arregla a los dos. Lo que ya falta se va recuperando solo a medida que entráis con la 1.1.2.
- **Colecta para abrir el banco:** el maestro de hermandad crea una colecta de oro (por defecto 100 de oro) y elige tesorero. Se dona dándole el oro al tesorero por intercambio (sin poner nada a cambio) o por correo: su addon lo apunta solo, así que la barra es la misma para todos y nadie se apunta oro de más. Cada moneda de oro da 2 de reputación y 2 insignias, quien dona queda como **fundador del banco** (sale en su ficha y en la placa de fundadores del banco) y la hermandad gana el logro **«Las arcas de la hermandad»** al llegar a la meta. Lo que sobra va al banco.
- **Lista de miembros:** ordénala por nombre, nivel, rango, insignias o zona (clic otra vez para invertir el orden) y oculta o muestra los desconectados. Se recuerda lo que elijas.
- **Barra de reputación más clara:** si ya tienes la reputación del rango siguiente y solo te falta antigüedad, la barra sale llena con un ✔ en lugar de «130 / 100». La reputación no tiene tope semanal; los topes de 100 son de insignias.

---

- **Fixed: everyone saw different kill counts** (e.g. in "Hunters of the week"). If you missed some of a guildmate's kills and then saw a newer one live, the earlier ones never reached you. On login the addon now compares how many kills and dungeons it has from each guildmate per day over the last three weeks and asks for the days that don't match. Whoever logs in also sends back what the responder was missing, so each login fixes both sides. Records already missing are recovered as people log in with 1.1.2.
- **Fundraiser to open the bank:** the guild master starts a gold fundraiser (100 gold by default) and picks a treasurer. Members donate by giving the treasurer gold by trade (asking nothing in return) or by mail: the treasurer's addon records it automatically, so everyone sees the same bar and nobody can add fake gold. Each gold coin gives 2 reputation and 2 badges, donors become **bank founders** (shown on their member card and on the bank's founders plaque) and the guild earns the **"The Guild Coffers"** achievement when the goal is reached. Any surplus goes into the bank.
- **Member list:** sort by name, level, rank, badges or zone (click again to reverse) and show or hide offline members. Your choice is remembered.
- **Clearer reputation bar:** if you already have the reputation for the next rank and only need more time in the guild, the bar shows full with a ✔ instead of "130 / 100". Reputation has no weekly cap; the 100 caps are for badges.

## 1.1.1 · 2026-11

- **Arreglado: las bajas y mazmorras de los demás no llegaban.** Al entrar, el addon pedía solo lo posterior a su último registro, así que una baja tuya reciente tapaba las de los demás de antes. Ahora pide lo que le falta de cada miembro. Funciona del todo cuando quien te contesta también tiene la 1.1.1: actualizad todos.
- **Bajas con honor:** cualquier baja que te dé honor vale 5 insignias. Las de jugadores grises siguen sin dar nada.
- **Las venganzas pagan siempre:** matar a quien acaba de matar a un compañero da 10 insignias + 5 de venganza, aunque no tenga hermandad o su hermandad no sea objetivo.
- **Tribus más baratas:** fundar una cuesta 50 insignias repartidas entre los fundadores; cada uno paga su parte al aceptar. Quien pagó 100 recupera la diferencia.
- **Avisos nuevos en el chat de hermandad:** logros de hermandad, subidas de nivel de hermandad y rangos de profesión (Oficial, Experto, Artesano…).
- **Escape cierra la ventana** de Guildmark (en combate no: ahí, la X).
- **Cartel nuevo para los logros de hermandad:** grande, arriba de la pantalla y con brillo si la hermandad tiene el aviso dorado. También sale uno cuando la hermandad sube de nivel. `/gmk aviso` enseña una muestra.
- **Arreglado: logros de hermandad repetidos en el chat** cuando alguien instala el addon o entra: ahora espera a la sincronización antes de anunciar y no anuncia lo que la hermandad ya tenía.

---

- **Fixed: other members' kills and dungeons weren't arriving.** On login the addon only asked for records newer than its latest one, so a recent kill of yours hid everyone else's earlier ones. It now asks for what it's missing from each member. It fully works once whoever answers you also has 1.1.1: everyone should update.
- **Honorable kills:** any kill that gives you honor is worth 5 badges. Grey players still give nothing.
- **Revenge always pays:** killing whoever just killed a guildmate gives 10 badges + 5 for revenge, even if they have no guild or their guild isn't a target.
- **Cheaper tribes:** founding one costs 50 badges split between the founders; each pays their share when accepting. Anyone who paid 100 gets the difference back.
- **New guild chat announcements:** guild achievements, guild level-ups and profession ranks (Journeyman, Expert, Artisan…).
- **Escape closes the Guildmark window** (not in combat: use the X there).
- **New banner for guild achievements:** large, at the top of the screen, with a shine if the guild has the golden alert. One also appears when the guild levels up. `/gmk toast` shows a sample.
- **Fixed: guild achievements announced again in chat** when someone installs the addon or logs in: it now waits for the sync before announcing, and skips anything the guild already had.

## 1.1.0 · 2026-11

- **Nuevo: sección Banco.** Lo que hay de verdad en el banco de la hermandad, como se ve en el juego (pestañas, huecos, cantidades y oro). Se actualiza cada vez que alguien con el addon abre el banco. El maestro decide en Ajustes qué rangos ven cada pestaña.
- **Peticiones al banco:** clic en un objeto para pedirlo. Llega a quien tenga el permiso nuevo «Entregar objetos del banco»; la retirada se comprueba con el registro del banco y la entrega con el intercambio (o se marca a mano).
- Los pedidos de depósito y el registro de aportaciones pasan del cofre a la sección Banco.
- **Encargos:** casilla «Pongo yo los materiales» con la lista de lo que pide la receta, y propina en oro, plata y cobre. El addon cuenta en el intercambio lo que llega (2/2, 0/1…) y si la propina está pagada.
- Logros nuevos: «Intendencia» y «Artesanos bien pagados».
- Arreglado: nombres de objetos que salían como número (en Forever cambió la función del juego para leerlos).
- El menú lateral se ajusta para no pisar Logros y Ajustes cuando una sección tiene muchos apartados.

Es la primera versión del banco: con hermandades grandes y muchas pestañas aún no está probado del todo. Si algo falla, `/gmk errores` y cuéntanoslo.

---

- **New: Bank section.** What is really inside the guild bank, laid out like the in-game bank (tabs, slots, stacks and gold). It updates every time someone with the addon opens the bank. The guild master chooses in Settings which ranks see each tab.
- **Bank requests:** click an item to request it. It goes to whoever has the new «Hand out bank items» permission; the withdrawal is checked against the bank log and the hand-over in the trade window (or marked manually).
- Deposit requests and the contribution log move from the chest to the Bank section.
- **Orders:** «I'll provide the materials» checkbox with the recipe's reagent list, and a tip in gold, silver and copper. The addon counts what arrives in trades (2/2, 0/1…) and whether the tip was paid.
- New achievements: «Quartermasters» and «Well-Paid Crafters».
- Fixed: item names showing as numbers (Forever changed the game function that reads them).
- The side menu shrinks so it no longer covers Achievements and Settings when a section has many tabs.

This is the first bank release: large guilds with many tabs are not fully tested yet. If something breaks, `/gmk errors` and tell us.

## 1.0.0 · 2026-10

Primera versión estable, ya pública para todo el mundo.

- La medalla «Escudo de la facción» se llama «Escudo» en el estuche (el título que da el oro no cambia).
- API para complementos: `GuildmarkAPI.RegisterToastHandler` permite a otra interfaz pintar los avisos de logro de hermandad a su manera.

---

First stable release, now public for everyone.

- The «Shield of the Faction» medal is shown as «Shield» in the medal case (the gold title is unchanged).
- Add-on API: `GuildmarkAPI.RegisterToastHandler` lets another UI draw the guild achievement toasts its own way.

## 0.9.3 (beta) · 2026-10

- Nuevo: las ocho medallas del perfil tienen arte propio, con una imagen para bronce, plata y oro. También se ven junto al retrato.

---

- New: the eight profile medals have their own art, with an image for bronze, silver and gold. They also show next to the portrait.

## 0.9.2 (beta) · 2026-10

- Nuevo: `/gmk errores` abre una ventana con los errores del addon listos para copiar y avisar de un fallo (también desde Ajustes). No se envía nada a ningún sitio.
- Arreglado: la primera vez que se cargaba el addon podía salir el aviso de Blizzard de «acción bloqueada».
- Cabecera: el marco de la barra de reputación ya encaja con el relleno, y los iconos de insignias y cofre van sin fondo negro.

---

- New: `/gmk errors` opens a window with the addon errors ready to copy and report a bug (also from Settings). Nothing is sent anywhere.
- Fixed: the first time the addon loaded, Blizzard's "action blocked" warning could show up.
- Header: the reputation bar frame now fits the fill, and the badge and chest icons no longer have a black background.

## 0.9.1 (beta) · 2026-10

- Arreglado: la ventana daba un error al abrirse si tenías un encargo al gremio que aún no había aceptado nadie.

---

- Fixed: the window threw an error on opening if you had a guild-wide order nobody had accepted yet.

## 0.9.0 (beta) · 2026-10

Primera versión pública, en beta: casi todo está probado en la beta de WoW Forever, pero
algunas partes solo se podrán comprobar del todo con el juego final (campos de batalla,
mazmorras por estadística, temporada JcJ y el banco de la hermandad con sus permisos).
Si algo falla, avísanos.

- **Hermandad:** quién está conectado y qué hace, fichas de miembros, tribus, clasificación, crónica, cofre de hermandad con proyectos y banco de la hermandad con pedidos.
- **Eventos** con calendario, inscripción por rol y asistencia automática.
- **JcE:** buscador de grupo interno, tiempos y mazmorras completadas.
- **JcJ:** objetivos de caza, cabezas con precio y botín de guerra, auxilio y asaltos a capitales con tu facción, campos de batalla.
- **Facción:** clasificación de hermandades, directorio, récords y Horda contra Alianza.
- **Mercado:** subasta con insignias, gremios de artesanos, encargos y tienda.
- **Perfil:** estuche de medallas, ficha de rol e insignias del retrato.
- **Logros de hermandad** con nivel (1 a 10) y recompensas.
- **Rangos y permisos** decididos por el maestro de la hermandad, y anuncios en el chat de hermandad.

---

First public release, in beta: almost everything has been tested on the WoW Forever beta,
but some parts can only be fully checked on the live game (battlegrounds, dungeons by
statistic, PvP season and the guild bank with its permissions). If something breaks, let us
know.

- **Guild:** who is online and what they are doing, member cards, tribes, ranking, chronicle, a guild chest with projects and the guild bank with requests.
- **Events** with a calendar, sign-up by role and automatic attendance.
- **PvE:** internal group finder, times and completed dungeons.
- **PvP:** hunting targets, bounties and war spoils, calls for help and capital assaults with your faction, battlegrounds.
- **Faction:** guild ranking, directory, records and Horde vs Alliance.
- **Market:** badge auction, crafter guilds, orders and shop.
- **Profile:** medal case, character sheet and portrait badges.
- **Guild achievements** with a level (1 to 10) and rewards.
- **Ranks and permissions** set by the guild master, and announcements in guild chat.
