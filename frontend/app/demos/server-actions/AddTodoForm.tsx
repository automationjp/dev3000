"use client";

import { useRef } from "react";
import { useFormStatus } from "react-dom";
import { addTodo } from "./actions";

function SubmitButton() {
  const { pending } = useFormStatus();

  return (
    <button
      type="submit"
      disabled={pending}
      className="px-6 py-3 bg-gradient-to-r from-cyan-500 to-blue-500 hover:from-cyan-600 hover:to-blue-600 disabled:from-gray-500 disabled:to-gray-600 text-white font-semibold rounded-lg transition-all duration-300 disabled:cursor-not-allowed"
    >
      {pending ? "Adding..." : "Add Todo"}
    </button>
  );
}

export default function AddTodoForm() {
  const formRef = useRef<HTMLFormElement>(null);

  async function handleSubmit(formData: FormData) {
    const result = await addTodo(formData);
    if (result.error) {
      // Consider using a toast notification or inline error message
      console.error(result.error);
    } else {
      formRef.current?.reset();
    }
  }

  return (
    <form ref={formRef} action={handleSubmit} className="flex gap-4">
      <input
        type="text"
        name="text"
        placeholder="Enter a new todo..."
        className="flex-1 px-4 py-3 bg-gray-900/50 border border-gray-600 rounded-lg text-white placeholder-gray-500 focus:outline-none focus:border-cyan-500 transition-colors"
        required
      />
      <SubmitButton />
    </form>
  );
}

