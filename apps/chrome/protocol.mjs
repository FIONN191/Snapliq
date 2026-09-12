export const HOST="com.snapliq.desktop.development";
export const ACTIONS=Object.freeze(["ping","capture","record","settings"]);
export function request(action,requestId){if(!ACTIONS.includes(action))throw new Error("Unsupported action");return {action,requestId:String(requestId).slice(0,128)}}
export function responseStatus(reply,action){
 if(!reply||reply.ok!==true){const errors={desktop_not_running:"桌面应用尚未运行。点击截图或录屏可尝试启动。",desktop_timeout:"桌面应用没有及时回应，请从菜单栏或托盘检查状态。",invalid_request:"请求格式不受支持，请更新扩展与桌面应用。"};return errors[reply?.error]||"无法连接桌面应用，请在 Snapliq 设置中重新连接此扩展。"}
 if(action==="ping")return "桌面应用已连接 · "+(reply.version||"Snapliq");
 return {capture:"截图请求已发送，请在桌面中框选。",record:"录屏来源选择已请求，请在桌面应用中继续。",settings:"已请求打开桌面设置。"}[action];
}
