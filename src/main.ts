// Point d'entrée : langue, état, carte, interface.

import 'maplibre-gl/dist/maplibre-gl.css';
import './styles.css';
import { App } from './app';
import { initLanguage, t } from './i18n';
import { registerServiceWorker } from './offline/manager';
import { initialState, Store } from './state';
import { Ui } from './ui/ui';

initLanguage();
registerServiceWorker(import.meta.env.BASE_URL);

const mapElement = document.getElementById('map');
const uiElement = document.getElementById('ui');

if (mapElement && uiElement) {
  try {
    const app = new App(new Store(initialState()), mapElement);
    new Ui(app, uiElement);
    void app.start();
  } catch (error) {
    // Le plus souvent : WebGL indisponible sur cet appareil.
    console.error(error);
    const message = document.createElement('p');
    message.className = 'fatal';
    message.textContent = t('app.noWebgl');
    uiElement.replaceChildren(message);
  }
}
