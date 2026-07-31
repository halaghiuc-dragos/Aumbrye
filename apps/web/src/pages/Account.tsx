import { FormEvent, useState } from "react";
import { getSave, login, register } from "../api/client";

export default function AccountPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [token, setToken] = useState(localStorage.getItem("aumbrye_token") ?? "");
  const [character, setCharacter] = useState<string>("");
  const [message, setMessage] = useState("");

  async function handleLogin(e: FormEvent) {
    e.preventDefault();
    const data = await login(email, password);
    if (data.error) {
      setMessage(data.error);
      return;
    }
    const access = data.tokens?.accessToken ?? "";
    setToken(access);
    localStorage.setItem("aumbrye_token", access);
    setMessage("Logged in.");
    await loadCharacter(access);
  }

  async function handleRegister(e: FormEvent) {
    e.preventDefault();
    const data = await register(email, password);
    if (data.error) {
      setMessage(data.error);
      return;
    }
    setMessage("Registered — you can log in now.");
  }

  async function loadCharacter(access: string) {
    const save = await getSave(access);
    if (save.state) {
      try {
        const parsed = JSON.parse(save.state);
        const name = parsed.character?.name ?? "Wanderer";
        const level = parsed.character?.level ?? 1;
        setCharacter(`${name} — Level ${level}`);
      } catch {
        setCharacter("Save loaded");
      }
    }
  }

  return (
    <section className="page">
      <h2>Account</h2>
      {token ? (
        <div className="card">
          <p>Signed in.</p>
          {character && <p>{character}</p>}
          <button type="button" onClick={() => loadCharacter(token)}>
            Refresh character
          </button>
        </div>
      ) : (
        <form className="card form" onSubmit={handleLogin}>
          <label>
            Email
            <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
          </label>
          <label>
            Password
            <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required />
          </label>
          <div className="form-actions">
            <button type="submit">Log in</button>
            <button type="button" onClick={handleRegister}>
              Register
            </button>
          </div>
        </form>
      )}
      {message && <p className="muted">{message}</p>}
      <p className="muted">OAuth (Google/Discord) deferred to post-EA — see known issues.</p>
    </section>
  );
}
