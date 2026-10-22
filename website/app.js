const hero = document.querySelector('#hero-video');
const motion = document.querySelector('#toggle-motion');
const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
let userPaused = reduced.matches || Boolean(navigator.connection?.saveData);

function updateMotion() {
  const paused = userPaused || document.hidden;
  motion.setAttribute('aria-pressed', String(userPaused));
  motion.setAttribute('aria-label', userPaused ? 'Play animation' : 'Pause animation');
  hero.parentElement.classList.toggle('motion-enabled', !userPaused);
  if (paused) hero.pause();
  else hero.play().catch(() => {
    userPaused = true;
    motion.setAttribute('aria-pressed', 'true');
    motion.setAttribute('aria-label', 'Play animation');
  });
}
motion.addEventListener('click', () => { userPaused = !userPaused; updateMotion(); });
reduced.addEventListener('change', () => { userPaused = reduced.matches; updateMotion(); });
document.addEventListener('visibilitychange', updateMotion);
updateMotion();

const filmDialog = document.querySelector('#film-dialog');
const installDialog = document.querySelector('#install-dialog');
const film = document.querySelector('#launch-film');
document.querySelector('#watch-film').addEventListener('click', () => {
  filmDialog.showModal();
  hero.pause();
  film.play().catch(() => {});
});
filmDialog.addEventListener('close', () => { film.pause(); updateMotion(); });
document.querySelector('#open-install').addEventListener('click', () => installDialog.showModal());
for (const dialog of [filmDialog, installDialog]) {
  dialog.querySelector('.close-dialog').addEventListener('click', () => dialog.close());
  dialog.addEventListener('click', event => {
    if (event.target !== dialog) return;
    const box = dialog.getBoundingClientRect();
    if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) dialog.close();
  });
}
