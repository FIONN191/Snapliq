import {HOST,request,responseStatus} from "./protocol.mjs";
const status=document.querySelector("#status"),buttons=[...document.querySelectorAll("[data-action]")];
async function send(action){buttons.forEach(b=>b.disabled=true);try{const reply=await chrome.runtime.sendNativeMessage(HOST,request(action,crypto.randomUUID()));status.textContent=responseStatus(reply,action)}catch{status.textContent="尚未连接。请在 Snapliq 桌面设置中点击“连接 Snapliq for Chrome”，然后重试。"}finally{buttons.forEach(b=>b.disabled=false)}}
buttons.forEach(b=>b.addEventListener("click",()=>send(b.dataset.action)));send("ping");

const theme=matchMedia("(prefers-color-scheme:dark)");
function adaptToolbarIcon(){const prefix=theme.matches?"white-":"";chrome.action.setIcon({path:{16:"icons/"+prefix+"16.png",32:"icons/"+prefix+"32.png"}}).catch(()=>{})}
adaptToolbarIcon();theme.addEventListener("change",adaptToolbarIcon);
