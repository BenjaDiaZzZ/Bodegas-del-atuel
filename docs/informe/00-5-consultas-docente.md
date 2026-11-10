# 0.5 · Consultas al docente

**Responsable:** P3 (API)
**Dependencias:** 0.4 (stack decidido) para poder formular las dudas de
despliegue y alcance.

## Objetivo

Enviar al docente, en un solo mensaje, las dudas de la sección 11 del
enunciado, y guardar las respuestas en `docs/decisiones.md`. El criterio de
«hecho» es que las consultas queden respondidas o anotadas como pendientes en
ese archivo.

## Entregable

`docs/decisiones.md` con las respuestas o, si no hubo respuesta, el estado de
cada consulta. El archivo no existe en el repositorio.

## Consultas de la sección 11

| # | Consulta | Estado en el enunciado |
|---|---|---|
| 1 | Fecha de entrega y fecha de defensa | «a definir» |
| 2 | Coeficiente de la nota individual | el enunciado dice «[Completar]» |
| 3 | Anexo C de preguntas típicas de defensa | el documento termina en Anexo B; el Anexo C no está |
| 4 | Restricciones o proveedores de nube recomendados para estudiantes | sin respuesta en el enunciado |

## Evidencia

- `docs/decisiones.md` no existe (`ls docs/decisiones.md` devuelve «No such file
  or directory»).
- No hay issue, PR ni comentario que registre el envío del mensaje al docente.
- No hay respuestas guardadas ni capturas en el repositorio.

No se encontró evidencia de que las consultas se hayan enviado. Tampoco se
encontró evidencia de que el docente haya respondido. Por lo tanto, el estado
es **Pendiente**, no «respondido».

## Verificación

```text
$ ls docs/decisiones.md
ls: cannot access 'docs/decisiones.md': No such file or directory

$ ls docs/
bocetos
contratos.md
diccionario.md
guion_demo.md
informe
justificaciones.md
normalizacion.md
tablero.md
trazabilidad.md
```

La lista de `docs/` confirma que no hay un archivo de decisiones ni un registro
equivalente.

## Estado

**Pendiente.** No hay consultas enviadas ni respuestas registradas. El
entregable `docs/decisiones.md` no existe.

## Próximos pasos

1. Redactar un único mensaje con las cuatro consultas de la tabla, sin
   agregar preguntas sueltas que ya estén resueltas en el enunciado.
2. Enviarlo por el canal acordado con el docente y conservar la fecha y el
   medio de envío.
3. Crear `docs/decisiones.md` con una fila por consulta: pregunta, fecha de
   envío, respuesta y estado. Si no hay respuesta, dejarla como «pendiente»
   con la fecha del recordatorio.
4. Si el Anexo C no aparece, pedirlo explícitamente; no asumir su contenido.

La creación de `docs/decisiones.md` queda fuera de la superficie autorizada de
este informe, por lo que no se creó aquí. Es una acción del equipo.

## Observaciones

- La consulta 3 (Anexo C) es la única que puede bloquear la preparación de la
  defensa: sin el anexo no se conocen las preguntas típicas.
- La consulta 4 condiciona la Fase 8; `docs/informe/08-nube.md` ya eligió Aiven
  Free como proveedor principal y documentó sus límites, pero esa decisión no
  reemplaza la respuesta del docente.
