import type {ButtonHTMLAttributes, InputHTMLAttributes, PropsWithChildren, SelectHTMLAttributes, TextareaHTMLAttributes} from 'react';

export function Button({children, ...props}: PropsWithChildren<ButtonHTMLAttributes<HTMLButtonElement>>) { return <button className="ui-button" {...props}>{children}</button>; }
export function Input(props: InputHTMLAttributes<HTMLInputElement>) { return <input className="ui-input" {...props} />; }
export function Textarea(props: TextareaHTMLAttributes<HTMLTextAreaElement>) { return <textarea className="ui-input" {...props} />; }
export function Card({children}: PropsWithChildren) { return <section className="ui-card">{children}</section>; }
export function Badge({children}: PropsWithChildren) { return <span className="ui-badge">{children}</span>; }
export function Alert({children}: PropsWithChildren) { return <p className="ui-alert" role="alert">{children}</p>; }
export function Select(props: SelectHTMLAttributes<HTMLSelectElement>) { return <select className="ui-input" {...props} />; }
export function Checkbox(props: InputHTMLAttributes<HTMLInputElement>) { return <input type="checkbox" {...props} />; }
export function RadioGroup({children}: PropsWithChildren) { return <div role="radiogroup">{children}</div>; }
export function Dialog({children}: PropsWithChildren) { return <section role="dialog" className="ui-card">{children}</section>; }
export function TableShell({children}: PropsWithChildren) { return <div className="ui-card" role="region">{children}</div>; }
export function Tabs({children}: PropsWithChildren) { return <div role="tablist">{children}</div>; }
export function DropdownMenu({children}: PropsWithChildren) { return <div>{children}</div>; }
export function Toast({children}: PropsWithChildren) { return <div role="status" className="ui-alert">{children}</div>; }
export function EmptyState({children}: PropsWithChildren) { return <div className="ui-card">{children}</div>; }
export function LoadingState({children}: PropsWithChildren) { return <div aria-live="polite">{children}</div>; }
export function PageHeader({children}: PropsWithChildren) { return <header className="page-header">{children}</header>; }
