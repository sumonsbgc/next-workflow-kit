import Link from 'next/link'

export default function Home() {
  return (
    <section>
      <h1>Projects app</h1>
      <Link href="/projects">Your projects</Link>
    </section>
  )
}
